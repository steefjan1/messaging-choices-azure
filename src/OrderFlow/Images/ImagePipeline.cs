using System.Text.Json;
using Azure.Messaging.EventGrid;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using OrderFlow.Contracts;

namespace OrderFlow.Images;

/// <summary>
/// Event Grid tells us a blob arrived. It does not do the work.
///
/// Whoever uploaded the image (the demo script, a back-office tool, an SFTP drop) has no
/// idea this pipeline exists and has no expectation about it. That is Microsoft Learn's
/// definition of an event. Event Grid pushes it here with retries (30 attempts over
/// 24 hours by default) and no ordering guarantee.
///
/// The actual processing goes on a Storage queue: it's cheap background work, nobody
/// waits for it, and a queue lets the worker take its time and retry at its own pace.
/// Event Grid is a router, not a work queue.
/// </summary>
public sealed class OnImageUploaded(ILogger<OnImageUploaded> logger)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    [Function(nameof(OnImageUploaded))]
    [QueueOutput(Names.ImageJobsQueue, Connection = Names.WorkStorageConnection)]
    public string Run([EventGridTrigger] EventGridEvent gridEvent)
    {
        // Subject looks like /blobServices/default/containers/product-images/blobs/<name>
        var blobName = gridEvent.Subject[(gridEvent.Subject.IndexOf("/blobs/", StringComparison.Ordinal) + "/blobs/".Length)..];

        using var data = JsonDocument.Parse(gridEvent.Data.ToString());
        var url = data.RootElement.GetProperty("url").GetString() ?? string.Empty;
        var length = data.RootElement.TryGetProperty("contentLength", out var len) ? len.GetInt64() : 0;

        logger.LogInformation("EVENTGRID {EventType} for {BlobName} ({Length} bytes), event id {EventId}",
            gridEvent.EventType, blobName, length, gridEvent.Id);

        return JsonSerializer.Serialize(new ImageJob(blobName, url, length), Json);
    }
}

/// <summary>
/// Storage queue worker. Stand-in for "resize an image": it copies the blob to the
/// thumbnails container and stamps metadata. Real resizing needs an imaging library,
/// which isn't the point of this sample.
///
/// Anything named *corrupt* throws. After maxDequeueCount (3, in host.json) the Functions
/// host moves the message to image-jobs-poison. Storage itself has no dead-letter concept.
/// </summary>
public sealed class ImageWorker(BlobServiceClient blobs, ILogger<ImageWorker> logger)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    [Function(nameof(ImageWorker))]
    public async Task Run(
        [QueueTrigger(Names.ImageJobsQueue, Connection = Names.WorkStorageConnection)] string payload,
        FunctionContext context)
    {
        var job = JsonSerializer.Deserialize<ImageJob>(payload, Json)!;
        var dequeueCount = context.BindingContext.BindingData.TryGetValue("DequeueCount", out var dc) ? dc : "?";

        if (job.BlobName.Contains("corrupt", StringComparison.OrdinalIgnoreCase))
        {
            logger.LogWarning("IMAGE-WORKER cannot decode {BlobName}, dequeue {DequeueCount}", job.BlobName, dequeueCount);
            throw new InvalidDataException($"{job.BlobName} is not a valid image.");
        }

        var source = blobs.GetBlobContainerClient(Names.ImagesContainer).GetBlobClient(job.BlobName);
        var target = blobs.GetBlobContainerClient(Names.ThumbnailsContainer).GetBlobClient(job.BlobName);

        var content = await source.DownloadContentAsync();
        await target.UploadAsync(content.Value.Content, new BlobUploadOptions
        {
            Metadata = new Dictionary<string, string>
            {
                ["source"] = job.BlobName,
                ["processedBy"] = nameof(ImageWorker),
            },
        });

        logger.LogInformation("IMAGE-WORKER processed {BlobName} -> {Container}/{BlobName}",
            job.BlobName, Names.ThumbnailsContainer, job.BlobName);
    }
}
