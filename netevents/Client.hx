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

import netevents.Utils.*;

class Client {

    var sockets:{tIn:Thread, tOut:Thread};

    var events:Map<String, Dynamic->Void>;
    var host:String;
    var port:Int = 0;
    var mutex:Mutex;
    var disconnected:Bool = false;

    // Number of times to retry connecting before declaring failure.
    public var maxRetries:Int = 5;

    // How long to wait in between retrying connection.
    public var retrySpacing:Float = 2;


    public function new() {
        mutex = new Mutex();
        events = new Map();
    }

    // Call this to specify a callback for a given event type.
    // RESERVED EVENT NAMES which you should hook into:
    //      * __CONNECT     Called when a connection is established.
    //      * __RETRY       Called when attempting to connect for a second/third/.. time.
    //      * __FAILURE     Called when attempting to connect fails after X retries.
    //      * __DISCONNECT  Called when the connection is dropped.
    public function on(event:String, callback:Dynamic->Void) {
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

        var onFailure = events.get("__FAILURE");
        var onConnect= events.get("__CONNECT");
        var onDisconnect = events.get("__DISCONNECT");
        var onRetry = events.get("__RETRY");

        // Helpful "You might be doing something wrong" info
        if (onFailure == null || onConnect == null || onDisconnect == null) {
            print("info", "You should set hooks for __FAILURE, __CONNECT and __DISCONNECT before connecting!");
            print("info", "Otherwise your program will throw errors when networking goes wrong.");
        }

        var attempts:Int = 0;
        var failed:Bool = true;

        while(attempts++ < maxRetries) {
            try {
                sock.connect(new sys.net.Host(host),port);
                failed = false;
                break;
            }
            catch(e:Dynamic) {
                print("conn", 'Retrying... ("$e") [attempt $attempts of $maxRetries]');
                if(onRetry != null) onRetry(null);
                Sys.sleep(retrySpacing);
            }
        }

        if(failed) {
            print("conn", 'Connection failed after $maxRetries attempts.');
            if(onFailure != null) onFailure(null);
            else                  throw 'Connection failed.';
        }
        else {
            print("conn", "Connected!");
            print("conn", "Dispatching TCP send/rcv threads");

            sockets = {
                tIn:  Thread.create(socketInThread),
                tOut: Thread.create(socketOutThread)
            };

            sockets.tIn.sendMessage(sock);
            sockets.tOut.sendMessage(sock);

            if(onConnect != null) onConnect(null);
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

                printVerbose("recv", k);

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
            print("err", haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
            var onDisconnect = events.get("__DISCONNECT");
            if(onDisconnect == null) {
                throw "Disconnected from server.";
            }
            else {
                onDisconnect(null);
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
            var onDisconnect = events.get("__DISCONNECT");
            if(onDisconnect == null) {
                throw "Disconnected from server.";
            }
            else {
                onDisconnect(null);
            }
        }
    }

}

