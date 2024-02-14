namespace ScaleRESTService;

public interface ISerialPortFactory
{
    public ISerialPortWrapper Connect();
}

public interface ISerialPortWrapper : IDisposable
{
    public Task<string> Write(byte[] code, int timeout);
}