package netevents;

class Utils {

    // Helper function for printing connection data,.
    public static inline function print(type:String, data:String, ?pos:haxe.PosInfos) {
#if !NE_QUIET
        if (pos == null) {
            Sys.println('[ ${StringTools.lpad(type," ",10)} ] $data');
        }
        else {
            Sys.println('[ ${StringTools.lpad(type," ",10)} ] [${pos.fileName},${pos.lineNumber}] $data');
        }
#end

    }

    // Helper function for printing connection data,.
    public static inline function printVerbose(type:String, data:String, ?pos:haxe.PosInfos) {
#if NE_VERBOSE
        if (pos == null) {
            Sys.println('[ ${StringTools.lpad(type," ",10)} ] $data');
        }
        else {
            Sys.println('[ ${StringTools.lpad(type," ",10)} ] [${pos.fileName},${pos.lineNumber}] $data');
        }
#end

    }
}
