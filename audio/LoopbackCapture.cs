// loopcap - record what you hear and what you say into two wavs, until a stop file appears.
//
// ponytail: no virtual audio driver on Windows, and no output-device switching either.
// WASAPI has been able to record a *render* endpoint natively since Vista (loopback mode),
// which is the exact capability macOS withholds and BlackHole exists to fake. So the whole
// mac dance - install a driver, build a Multi-Output Device, switch the system output to it
// on start, switch it back on stop - collapses into "open the output device and read it".
// You keep hearing the call, the volume keys keep working, nothing is reconfigured.
using System;
using System.IO;
using System.Threading;
using NAudio.CoreAudioApi;
using NAudio.Wave;

class LoopCap
{
    static WaveFileWriter Attach(string path, IWaveIn src)
    {
        var w = new WaveFileWriter(path, src.WaveFormat);
        src.DataAvailable += (s, e) => { lock (w) w.Write(e.Buffer, 0, e.BytesRecorded); };
        return w;
    }

    static int Main(string[] args)
    {
        if (args.Length != 3)
        {
            Console.Error.WriteLine("usage: loopcap <sys.wav> <mic.wav> <stopfile>");
            return 2;
        }

        WasapiLoopbackCapture sys = null;
        WasapiCapture mic = null;
        WaveFileWriter sysW = null, micW = null;

        try { sys = new WasapiLoopbackCapture(); sysW = Attach(args[0], sys); }
        catch (Exception e) { Console.Error.WriteLine("no output device (them): " + e.Message); }

        try { mic = new WasapiCapture(); micW = Attach(args[1], mic); }
        catch (Exception e) { Console.Error.WriteLine("no input device (you): " + e.Message); }

        if (sys == null && mic == null) { Console.Error.WriteLine("nothing to record"); return 1; }

        // WASAPI loopback delivers no buffers at all while the output device is idle - a quiet
        // stretch goes *missing* from the file rather than landing in it as silence, so every
        // word after it plays early against the mic track and the two drift apart. The fix is
        // the documented one: play silence for the duration so the device never goes idle.
        WasapiOut keepAlive = null;
        if (sys != null)
        {
            keepAlive = new WasapiOut();
            keepAlive.Init(new SilenceProvider(sys.WaveFormat));
            keepAlive.Play();
        }

        if (sys != null) { Console.Error.WriteLine("them: " + sys.WaveFormat); sys.StartRecording(); }
        if (mic != null) { Console.Error.WriteLine("you:  " + mic.WaveFormat); mic.StartRecording(); }

        // ponytail: a stop file, not a signal. Windows has no clean way to ask another
        // process's child to finish, and killing it leaves an unfinalised RIFF header.
        while (!File.Exists(args[2])) Thread.Sleep(200);

        if (sys != null) sys.StopRecording();
        if (mic != null) mic.StopRecording();
        Thread.Sleep(400);  // let the last DataAvailable land before the writers close

        if (keepAlive != null) { keepAlive.Stop(); keepAlive.Dispose(); }
        if (sysW != null) { lock (sysW) sysW.Dispose(); }
        if (micW != null) { lock (micW) micW.Dispose(); }
        if (sys != null) sys.Dispose();
        if (mic != null) mic.Dispose();
        return 0;
    }
}
