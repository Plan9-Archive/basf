implement TestExactus;

include "sys.m";
include "draw.m";
include "arg.m";
include "lock.m";
include "string.m";

include "exactus.m";

sys: Sys;
str: String;

exactus: Exactus;
	ERmsg, Port: import exactus;

TestExactus: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

stdin, stdout, stderr: ref Sys->FD;

port: ref Port;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	
	stderr = sys->fildes(2);
	stdout = sys->fildes(1);
	stdin = sys->fildes(0);

	exactus = load Exactus Exactus->PATH;
	exactus->init();
	
	path := "tcp!iolan!exactus";
	skip := 0;
	
	arg := load Arg Arg->PATH;
	arg->init(argv);
	arg->setusage(arg->progname()+" [-s] [path]");
	while((c := arg->opt()) != 0)
		case c {
		's' =>	skip++;
		* =>	arg->usage();
		}
	
	argv = arg->argv();
	if(argv != nil)
		path = hd argv;
	
	if(path != nil && skip == 0) {
		port = exactus->open(path);
		if(port.ctl == nil || port.data == nil) {
			sys->fprint(stderr, "Failed to connect to %s\n", port.path);
			exit;
		}
	}
	
	testdata();

	if(port != nil && skip == 0)
		testnetwork(port);
	
	if(port != nil)
		exactus->close(port);
}

testnetwork(p: ref Exactus->Port)
{
}

testdata()
{
	b := array[] of {byte 16r44, byte 16r45, byte 16r00, byte 16r42, byte 16rC8,
					 byte 16r00, byte 16r00, byte 16r3F, byte 16r66, byte 16r66,
					 byte 16r66, byte 16r3F, byte 16r00, byte 16r00, byte 16r00};
	
	sys->fprint(stdout, "LRC of:%s\n", hexdump(b));
	sys->fprint(stdout, "LRC ==\t%0X\n", int exactus->lrc(b));
}


hexdump(b: array of byte): string
{
	s := "";
	for(i:=0; i<len b; i++) {
		if(i%8 == 0)
			s = s + "\n\t";
		s = sys->sprint("%s %02X", s, int(b[i]));
	}
	
	return str->drop(s, "\n");
}
