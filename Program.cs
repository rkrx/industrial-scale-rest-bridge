using System.Globalization;
using System.IO.Ports;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using ScaleRESTService;

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
    {
        return new SerialPort(ini.ComPort, ini.BaudRate, parity, ini.DataBits)
        {
            Handshake = handshake,
            WriteTimeout = 5000,
            ReadTimeout = 5000,
            DtrEnable = ini.DtrEnable,
            RtsEnable = ini.RtsEnable
        };
    }),
    true => new FakeSerialPortFactory(ini.TestModeResponse)
};

FeedbackChannel<byte[], double> requestChannel = new (async input =>
{
    using (var serialPort = serialPortFactory.Connect())
    {
        var result = await serialPort.Write(input, 3000);
        var part = IOUtils.Substring(result, ini.ResponseWeightStartIndex, ini.ResponseWeightPartLength);

        if (ini.ResponseUnitThousandsSeparator != null)
        {
            part = part.Replace(ini.ResponseUnitThousandsSeparator, "");
        }

        if (ini.ResponseUnitDecimalSeparator != null && ini.ResponseUnitDecimalSeparator != ".")
        {
            part = part.Replace(ini.ResponseUnitDecimalSeparator, ".");
        }
        
        part = Regex.Replace(part, "[^0-9.-]", "");

        double weight = double.Parse(part, CultureInfo.InvariantCulture);
        return ini.ResponseUnit switch {
            "kilogram" => weight,
            "gram" => weight * 0.001,
            "carat" => weight * 0.0002,
            "oz" => weight * 0.02835,
            "lb" => weight * 0.454,
            "lbs" => weight * 0.45359237,
            _ => throw new Exception("Invalid unit")
        };
    }
});

var requestCode = IOUtils.HexToByteArray(ini.RequestCodeHex);

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

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