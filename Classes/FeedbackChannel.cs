using System.Collections.Concurrent;

namespace ScaleRESTService;

public class FeedbackChannel<TI, TO> : IDisposable
{
    private readonly BlockingCollection<RequestResponse> _requestQueue = new (1);
    
    public FeedbackChannel(Func<TI, Task<TO>> handler)
    {
        Task.Run(async () =>
        {
            foreach (var requestResponse in _requestQueue.GetConsumingEnumerable())
            {
                try
                {
                    requestResponse.Response.SetResult(await handler(requestResponse.Input));
                }
                catch (Exception e)
                {
                    requestResponse.Response.SetException(e);
                }
            }
        });
    }

    public Task<TO> Request(TI input, int timeoutMilliseconds)
    {
        var requestResponse = new RequestResponse(input, new TaskCompletionSource<TO>());
        _requestQueue.Add(requestResponse);
        var response = requestResponse.Response.Task;
        var result = Task.WhenAny(response, Task.Delay(timeoutMilliseconds)).GetAwaiter().GetResult();
        if (response == result)
        {
            return response;
        }

        throw new TimeoutException();
    }

    public void Dispose()
    {
        _requestQueue.Dispose();
    }

    private record RequestResponse(TI Input, TaskCompletionSource<TO> Response);
}