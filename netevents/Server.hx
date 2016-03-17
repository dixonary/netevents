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

class Server {

    var clients:Map<Int,ClientInfo>;
    var events :Map<String, Dynamic->Void>;

    var port:Int = 0;
    var latestId:Int = 0;

    var mutex:Mutex;

    public function new():Void {
        port = Port;

        mutex = new Mutex();
        clients = new Map();
        events = new Map();
    }

    public function on(event:String, callback:Dynamic->Void) {
        mutex.acquire();
        events.set(event, callback);
        mutex.release();

        print("events", 'Added event handler "$event"');
    }

    public function listen(Port:Int) {
        port = Port;
        Thread.create(listenThread);
    }

    function listenThread():Void {

        var host:String = "0.0.0.0";

        var sock = new Socket();
        sock.bind(new sys.net.Host(host), port);
        sock.listen(10);

        print("server", 'Listening on $host:$port');

        while(true) {
            var s = sock.accept();
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
        var ser = haxe.Json.stringify({type:type, content:data});
        clients.get(id).outThread.sendMessage(ser);
    }
    public function broadcast(type:String, data:Dynamic) {
        var ser = haxe.Json.stringify({type:type, content:data});
        //trace("[ cast ] sending to "+socks.length+" clients");
        for(i in clients.iterator()) {
            i.outThread.sendMessage(ser);
        }
    }

    function socketInThread():Void {
        var client:ClientInfo           = Thread.readMessage(true);

        try {
            while(true) {
                var k = client.socket.input.readLine();

                print("recv", k);

                var c:{type:String, content:Dynamic} = haxe.Json.parse(k);

                if(c.type == null || c.type == "") {
                    print("recv", "Received data has no TYPE - discarding");
                    continue;
                }

                mutex.acquire();
                var callback:Null<Dynamic->Void> = events.get(c.type);
                if(callback == null) {
                    print("recv", 'Received data type "${c.type}" has no callback - discarding');
                }
                else {
                    callback(c.content);
                }
                mutex.release();
            }
        }
        catch(e:Dynamic) {
            print("err", '$e - attempting recovery');
            print("dcon", 'Client id ${client.id} (${client.name}) disconnected.');
            if(client.socket == null) return;
            clients.remove(client.id);
        }
    }

    // Thread which deals with the outgoing sockets.
    function socketOutThread():Void {
        var client:ClientInfo           = Thread.readMessage(true);
        try {
            while(true) {
                var k:String = Thread.readMessage(true);
                if(client == null || client.socket == null) return;
                print("send", k);
                client.socket.write(k+"\n");
            }
        }
        catch(e:Dynamic) {
            print("err", '$e - attempting recovery');
            print("dcon", 'Client id ${client.id} (${client.name}) disconnected.');
            clients.remove(client.id);
        }

    }


    // Helper function for printing connection data,.
    inline function print(type:String, data:String) {
#if NE_VERBOSE
        trace('[ ${StringTools.lpad(type," ",16)} ] $data');
#end
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