namespace ScaleRESTService;

using IniParser;
using IniData = IniParser.Model.IniData;

public class IniFile
{
    public string ListenToUrl => Get("service", "listen", "http://127.0.0.1:5000");
    public bool IsTestMode => bool.Parse(Get("service", "test-mode", "false"));
    public string TestModeResponse => Require("service", "test-mode-response", "Is is necessary to provide a test-mode-response in the ini file when test-mode is enabled.");
    public string? ComPort => Require("scale", "com-port", "The com-port is required to connect to the scale.");
    public Int32 BaudRate => Int32.Parse(Get("scale", "baud-rate", "9600"));
    public Int32 DataBits => Int32.Parse(Get("scale", "data-bits", "8"));
    public bool DtrEnable => bool.Parse(Get("scale", "dtr-enable", "true"));
    public bool RtsEnable => bool.Parse(Get("scale", "rts-enable", "true"));
    public string Parity => Get("scale" , "parity", "None");
    public string Handshake => Get("scale", "handshake", "XOnXOff");

    public Int32 ResponseWeightStartIndex => Int32.Parse(Get("scale", "scale-response-start-index", "0"));
    public Int32 ResponseWeightPartLength => Int32.Parse(Get("scale", "scale-response-part-length", "0"));
    public string RequestCodeHex => Require("scale", "trigger-code-byte-hex", "The trigger-code-byte-hex is required to trigger the scale.");
    public string? ResponseUnitDecimalSeparator => Get("scale", "scale-response-decimal-separator");
    public string? ResponseUnitThousandsSeparator => Get("scale", "scale-response-thousands-separator");
    public string ResponseUnit => Get("scale", "scale-response-unit", "kilogram");
    public string ResponseEndOfTransmission => Get("scale", "scale-response-eot", "\n");

    // Logging section properties
    public bool LogToConsole => IsLoggingEnabled("console");
    public string? LogToFile => Get("logging", "file");

    private readonly IniData _data;

    public IniFile(string filepath)
    {
        var parser = new FileIniDataParser();
        _data = parser.ReadFile(filepath);
    }

    private string? Get(string section, string key)
    {
        var value = _data[section][key];

        if (value == null) return value;
        
        value = value.Trim();
        value = IoUtils.TranslateNonVisibleCharacterPlaceholdersBack(value);

        if (value.StartsWith('"') && value.EndsWith('"'))
        {
            return value.Substring(1, value.Length - 2);
        }

        return value;
    }
    
    private string Require(string section, string key, string exceptionMessage)
    {
        var value = Get(section, key);
        if (value == null)
        {
            throw new Exception($"Missing ini variable: {section}.{key}: {exceptionMessage}");
        }

        return value;
    }

    private string Get(string section, string key, string defaultValue)
    {
        var value = Get(section, key);
        return value ?? defaultValue;
    }
    
    private bool IsLoggingEnabled(string key) {
        var value = Get("logging", key)?.ToLower();
        return value != null && value != "false" && value != "off";
    }
}