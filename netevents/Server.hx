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

class Server {

    var clients:Map<Int,ClientInfo>;
    var events :Map<String, Message->Void>;

    var host:String;
    var port:Int = 0;
    var latestId:Int = 0;

    var mutex:Mutex;

    public function new():Void {
        mutex = new Mutex();
        clients = new Map();
        events = new Map();
    }

    // Call this to specify a callback for a given event type.
    // RESERVED EVENT NAMES which you should use:
    //      * __READY
    //      * __DISCONNECT
    public function on(event:String, callback:Dynamic->Void) {
        mutex.acquire();
        events.set(event, callback);
        mutex.release();

        print("events", 'Added event handler "$event"');
    }

    public function listen(Host:String, Port:Int) {
        host = Host;
        port = Port;
        Thread.create(listenThread);
    }

    public function kick(id:Int) {
        var client = clients.get(id);
        if(client != null && client.socket != null) {
            client.socket.shutdown(true,true);
            client.socket.close();
        }
        clients.remove(id);
    }

    function listenThread():Void {

        var sock = new Socket();
        sock.bind(new sys.net.Host(host), port);
        sock.listen(10);

        print("server", 'Listening on $host:$port');

        var onReady = events.get("__READY");
        if(onReady != null) onReady(null);

        while(true) {
            var s = sock.accept();
            s.setTimeout(5);
            var cid = latestId++;
            var cName = s.peer().host.reverse();
            var tIn = Thread.create(socketInThread);
            var tOut = Thread.create(socketOutThread);

            var client = {id:cid,
                socket:s,
                name:cName,
                inThread:tIn,
                outThread:tOut};
            print("conn",'Connected to ${client.name} (id ${client.id} )');

            tIn.sendMessage(client);
            tOut.sendMessage(client);

            clients.set(cid, client);
        }

    }

    public function send(id:Int, type:String, data:Dynamic) {
        // Serialise and send anything.
        if(clients.get(id) == null) return;
        var ser = haxe.Json.stringify({type:type, content:data});
        clients.get(id).outThread.sendMessage(ser);
    }
    public function broadcast(type:String, data:Dynamic) {
        var ser = haxe.Json.stringify({type:type, content:data});
        //trace("[ cast ] sending to "+socks.length+" clients");
        for(i in clients) {
            i.outThread.sendMessage(ser);
        }
    }

    function socketInThread():Void {
        var client:ClientInfo           = Thread.readMessage(true);

        while(true) {
            try {
                var k = client.socket.input.readLine();

                printVerbose("recv", k);

                var c:{type:String, content:Dynamic} = haxe.Json.parse(k);

                if(c.type == null || c.type == "") {
                    print("recv", "Received data has no TYPE - discarding");
                    continue;
                }

                mutex.acquire();
                var callback:Null<Dynamic->Void> = events.get(c.type);
                // Call this to specify a callback for a given event type.
                if(callback == null) {
                    print("events", 'Received data type "${c.type}" has no callback - discarding');
                }
                else {
                    callback({client:client, content:c.content});
                }
                mutex.release();
            }
            catch(e:Dynamic) {
                print("itis", e.toString() == "Blocked");
                print("itwas", (e.indexOf("Blocked")).toString());
                if(e.indexOf("Blocked") != -1) continue;
                print("err", '$e');
                print("err", haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
                print("dcon", 'Client id ${client.id} (${client.name}) disconnected.');
                if(client.socket == null) return;

                var onDC = events.get("__DISCONNECT");
                if(onDC != null)  onDC({client:client, content:null});

                clients.remove(client.id);
                break;
            }
        }
    }

    // Thread which deals with the outgoing sockets.
    function socketOutThread():Void {
        var client:ClientInfo           = Thread.readMessage(true);
        while(true) {
            try {
                var k:String = Thread.readMessage(true);
                if(client == null || client.socket == null) return;
                printVerbose("send", k);
                client.socket.write(k+"\n");
            }
            catch(e:Dynamic) {
                print("err", '$e - attempting recovery');
                print("dcon", 'Client id ${client.id} (${client.name}) disconnected.');
                clients.remove(client.id);
            }
        }

    }

}

typedef Message = {
    client:ClientInfo,
    content:Dynamic
}

typedef ClientInfo = {
    id:Int,
    name:String,
    socket:Socket,
    inThread:Thread,
    outThread:Thread
}
