namespace ScaleRESTService;

public class FakeSerialPortFactory : ISerialPortFactory
{
    private readonly string _output;

    public FakeSerialPortFactory(string output)
    {
        this._output = output;
    }

    public ISerialPortWrapper Connect()
    {
        return new FakeSerialPortWrapper(_output);
    }

    public class FakeSerialPortWrapper : ISerialPortWrapper
    {
        private readonly string _output;

        public FakeSerialPortWrapper(string output)
        {
            _output = output;
        }

        public Task<string> Write(byte[] code, int timeout)
        {
            return Task.FromResult(_output);
        }

        public void Dispose()
        {
        }
    }
}