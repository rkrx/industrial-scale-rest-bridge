namespace ScaleRESTService;

public class FakeSerialPortFactory(string output) : ISerialPortFactory
{
    public ISerialPortWrapper Connect()
    {
        return new FakeSerialPortWrapper(output);
    }

    private class FakeSerialPortWrapper : ISerialPortWrapper
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