package netevents;

#if neko
import neko.vm.Thread;
import neko.vm.Mutex;
#elseif cpp
import cpp.vm.Thread;
import cpp.vm.Mutex;
#elseif java
import java.vm.Thread;
import java.vm.Mutex;
#else
#error "Netevents not implemented on this platform."
#end
import sys.net.Host;
import sys.net.Socket;

using Utils;

class Client {

    var sockets:{tIn:Thread, tOut:Thread};

    var events:Map<String, Dynamic->Void>;
    var host:String;
    var port:Int = 0;
    var connected:Bool = false;

    // Callback if the client and server become disconnected.
    // Default behaviour is to error.
    public var onDisconnect:Void->Void;

    // Callback if the client needs to retry connecting.
    // Default behaviour is to do nothing.
    public var onRetry     :Void->Void;

    // Callback if the client is unable to connect.
    // Default behaviour is to error.
    public var onFailure   :Void->Void;

    // Callback if the client connects to a server.
    // Default behaviour is to do nothing.
    public var onConnect   :Void->Void;

    // Number of times to retry connecting before declaring failure.
    public var maxRetries:Int = 5;

    // How long to wait in between retrying connection.
    public var retrySpacing:Float = 2;


    public function new() {
        mutex = new Mutex();
        clients = new Map();
        events = new Map();
    }

    // Call this to specify a callback for a given event type.
    public function registerEvent(event:String, callback:Dynamic->Void) {
        mutex.acquire();
        events.set(event, callback);
        mutex.release();

        print("events", 'Added event handler "$event"');
    }

    public function connect(Host:String, Port:Int) {
        host = Host;
        port = Port;
        Thread.create(connectThread);
    }

    public function connectThread() {
        var sock = new Socket();

        // Helpful "You might be doing something wrong" info
        if (onFailure == null || onConnect == null || onDisconnect == null) {
            print("info", "You should set onFailure(), onConnect() and onDisconnect() before connecting!");
            print("info", "Otherwise your program will throw errors when networking goes wrong.");
        }

        var attempts:Int = 0;
        var failed:Bool = true;

        while(attempts++ <= maxRetries) {
            try {
                sock.connect(new sys.net.Host(Host),Port);
                failed = false;
                break;
            }
            catch(e:Dynamic) {
                print("conn", 'Retrying... ("$e") [attempt $attempts of $maxRetries]');
                Sys.sleep(retrySpacing);
            }
        }

        if(failed) {
            print("conn", 'Connection failed after $maxRetries attempts.');
            if(onFailure != null) onFailure();
            else                  error('Connection failed.');
        }
        else {
            print("conn", "Connected!");
            print("conn", "Dispatching TCP send/rcv threads");

            sockets = {
                tIn:  Thread.create(inSockTCP),
                tOut: Thread.create(outSockTCP)
            };

            sockets.tIn.sendMessage(sock);
            sockets.tOut.sendMessage(sock);

            if(onConnect != null) onConnect();
        }

    }

    public function send(type:String, data:Dynamic):Void {
        sockets.tOut.sendMessage(haxe.Json.stringify({type:type,content:data}));
    }

    //Reads data from a TCP socket.
    public function socketInThread():Void {
        var sock:Socket = Thread.readMessage(true);

        try {
            while(true) {
                var k = sock.input.readLine();

                printVerbose(recv, k);

                var c:{type:String, content:Dynamic} = haxe.Json.parse(k);

                if(c.type == null || c.type == "") {
                    print("recv", "Received data has no TYPE - discarding");
                    continue;
                }

                mutex.acquire();
                var callback:Null<Dynamic->Void> = events.get(c.type);
                if(callback == null) {
                    print("events", 'Received data type "${c.type}" has no callback - discarding');
                }
                else {
                    callback(c.content);
                }
                mutex.release();

            }
        }
        catch(e:Dynamic) {
            print("err", '$e - disconnected');
            if(disconnected) return;
            if(onDisconnect == null) {
                error("Disconnected from server.");
            }
            else {
                onDisconnect();
            }
        }
    }

    //Writes data to a TCP socket.
    public function socketOutThread():Void {
        var sock:Socket = Thread.readMessage(true);

        try {
            while(true) {
                var k:String = Thread.readMessage(true);
                printVerbose("send", k);
                sock.write(k+"\n");
            }
        }
        catch(e:Dynamic) {
            print("err", '$e - disconnected');
            if(disconnected) return;
            if(onDisconnect == null) {
                error("Disconnected from server.");
            }
            else {
                onDisconnect();
            }
        }
    }

}

