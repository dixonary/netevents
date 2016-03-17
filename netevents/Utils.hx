package netevents;

class Utils {

    // Helper function for printing connection data,.
    public static inline function print(type:String, data:String) {
#if !NE_QUIET
        trace('[ ${StringTools.lpad(type," ",16)} ] $data');
#end

    }

    // Helper function for printing connection data,.
    public static inline function printVerbose(type:String, data:String) {
#if NE_VERBOSE
        trace('[ ${StringTools.lpad(type," ",16)} ] $data');
#end

    }
}
