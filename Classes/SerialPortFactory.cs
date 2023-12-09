namespace ScaleRESTService;

using System.IO.Ports;
using System.Text;

public class SerialPortFactory : ISerialPortFactory
{
    private readonly Func<SerialPort> _factory;
    private readonly string _endOfTransmissionSequence;

    public SerialPortFactory(string endOfTransmissionSequence, Func<SerialPort> factory)
    {
        _endOfTransmissionSequence = endOfTransmissionSequence;
        _factory = factory;
    }

    public ISerialPortWrapper Connect()
    {
        return new SerialPortWrapper(_factory(), _endOfTransmissionSequence);
    }
    
    private class SerialPortWrapper : IDisposable, ISerialPortWrapper
    {
        private readonly TaskCompletionSource<string> _result = new();
        private readonly SerialPort _serialPort;
        
        public SerialPortWrapper(SerialPort serialPort, string endOfTransmissionSequence)
        {
            _serialPort = serialPort;
            _serialPort.DataReceived += (object sender, SerialDataReceivedEventArgs e) =>
            {
                try
                {
                    _result.SetResult(_serialPort.ReadTo(endOfTransmissionSequence));
                }
                catch(Exception ex)
                {
                    _result.TrySetException(ex);
                }
            };
            _serialPort.Open();
        }

        public Task<string> Write(byte[] code, int timeout)
        {
            DebugWriteLine($"Request: {Encoding.ASCII.GetString(code)}");
            _serialPort.ReadExisting(); // Drain the buffer before making a new inquiry
            _serialPort.Write(code, 0, code.Length);
            var completedTask = Task.WhenAny(_result.Task, Task.Delay(timeout)).GetAwaiter().GetResult();
            if (completedTask == _result.Task)
            {
                DebugWriteLine($"Response: {_result.Task.Result}");
                return _result.Task;
            }

            throw new TimeoutException();
        }
        
        public void Dispose()
        {
            _serialPort.Close();
        }

        private void DebugWriteLine(string output)
        {
            Console.WriteLine(IOUtils.FormatNonvisibleCharacters(output));
        }
    }
}