using System.Globalization;
using System.IO.Ports;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using ScaleRESTService;
using System.IO;

if (args.Any(arg => arg == "--list-comports"))
{
    Console.WriteLine($"Available COM Ports: {String.Join(", ", SerialPort.GetPortNames())}");
    return;
}

var ini = new IniFile("settings.ini");

if (!Parity.TryParse(ini.Parity, out Parity parity))
{
    throw new Exception("Missing ini variable or invalid value: scale.parity");
}

if (!Handshake.TryParse(ini.Handshake, out Handshake handshake))
{
    throw new Exception("Missing ini variable or invalid value: scale.handshake");
}

ISerialPortFactory serialPortFactory = ini.IsTestMode switch
{
    false => new SerialPortFactory(ini.ResponseEndOfTransmission, () => 
        new SerialPort(ini.ComPort, ini.BaudRate, parity, ini.DataBits)
        {
            Handshake = handshake,
            WriteTimeout = 5000,
            ReadTimeout = 5000,
            DtrEnable = ini.DtrEnable,
            RtsEnable = ini.RtsEnable
        }),
    true => new FakeSerialPortFactory(ini.TestModeResponse)
};

FeedbackChannel<byte[], double> requestChannel = new (async input =>
{
    using var serialPort = serialPortFactory.Connect();
    
    var result = await serialPort.Write(input, 3000);
    var part = IoUtils.Substring(result, ini.ResponseWeightStartIndex, ini.ResponseWeightPartLength);

    if (ini.ResponseUnitThousandsSeparator != null)
    {
        part = part.Replace(ini.ResponseUnitThousandsSeparator, "");
    }

    if (ini.ResponseUnitDecimalSeparator != null && ini.ResponseUnitDecimalSeparator != ".")
    {
        part = part.Replace(ini.ResponseUnitDecimalSeparator, ".");
    }
        
    part = Regex.Replace(part, "[^0-9.-]", "");

    var weight = double.Parse(part, CultureInfo.InvariantCulture);
    return ini.ResponseUnit switch {
        "kilogram" => weight,
        "gram" => weight * 0.001,
        "carat" => weight * 0.0002,
        "oz" => weight * 0.02835,
        "lb" => weight * 0.454,
        "lbs" => weight * 0.45359237,
        _ => throw new Exception("Invalid unit")
    };
});

var requestCode = IoUtils.HexToByteArray(ini.RequestCodeHex);

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

TextWriter? logWriter = null;
if (ini.LogToFile != null) {
    logWriter = new StreamWriter(ini.LogToFile, true);
}

// Middleware to log requests and responses
app.Use(async (context, next) => {
    var requestPath = context.Request.Path;
    var requestMethod = context.Request.Method;
    var requestTime = DateTime.Now;
    var requestMessage = $"[{requestTime:yyyy-MM-dd HH:mm:ss}] {requestMethod} {requestPath}";
    
    if (ini.LogToConsole) {
        Console.WriteLine(requestMessage);
    }
    
    // Log request to file if configured
    logWriter?.WriteLine(requestMessage);
    logWriter?.Flush();
    
    // Capture the original body stream
    var originalBodyStream = context.Response.Body;
    
    try {
        // Create a new memory stream to capture the response
        using var responseBody = new MemoryStream();
        context.Response.Body = responseBody;
        
        // Continue processing the request
        await next.Invoke();
        
        // Read the response body
        responseBody.Seek(0, SeekOrigin.Begin);
        var responseText = await new StreamReader(responseBody).ReadToEndAsync();
        responseBody.Seek(0, SeekOrigin.Begin);
        
        var responseTime = DateTime.Now;
        var statusCode = context.Response.StatusCode;
        var responseMessage = $"[{responseTime:yyyy-MM-dd HH:mm:ss}] Response {statusCode}: {responseText}";
        
        if (ini.LogToConsole) {
            Console.WriteLine(responseMessage);
        }
        
        // Log response to file if configured
        logWriter?.WriteLine(responseMessage);
        logWriter?.Flush();
        
        // Copy the captured response to the original stream
        await responseBody.CopyToAsync(originalBodyStream);
    } finally {
        // Restore the original stream
        context.Response.Body = originalBodyStream;
    }
});

app.MapGet("/current-weight/kg", async (HttpContext context) =>
{
    try
    {
        var response = await requestChannel.Request(requestCode, 2500);
        context.Response.Headers.Add("Content-Type", "application/json");
        return JsonConvert.SerializeObject(new { success = true, weight = response, unit = "kilogram" });
    }
    catch (Exception e) 
    {
        context.Response.Headers.Add("Content-Type", "application/json");
        context.Response.StatusCode = 500;
        return JsonConvert.SerializeObject(new { success = false, message = e.Message, unit = "kilogram" });
    }
});

app.Urls.Add(ini.ListenToUrl);

app.Run();

logWriter?.Dispose();