implement TestExactus;

include "sys.m";
include "draw.m";
include "arg.m";
include "math.m";
include "lock.m";
include "string.m";

include "modbus.m";
include "exactus.m";

sys: Sys;
math: Math;
lock: Lock;
	Semaphore: import lock;
str: String;

modbus: Modbus;
	TMmsg, RMmsg: import modbus;

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
	math = load Math Math->PATH;
	str = load String String->PATH;
	lock = load Lock Lock->PATH;
	if(lock == nil)
		raise "fail: could not load lock module";
	lock->init();
	
	stderr = sys->fildes(2);
	stdout = sys->fildes(1);
	stdin = sys->fildes(0);

	modbus = load Modbus Modbus->PATH;
	modbus->init();

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

purge(p: ref Port)
{
	p.rdlock.obtain();
	p.avail = array[0] of byte;
	p.rdlock.release();
}

testdata()
{
	b := array[] of {byte 16r44, byte 16r45, byte 16r00, byte 16r42, byte 16rC8,
					 byte 16r00, byte 16r00, byte 16r3F, byte 16r66, byte 16r66,
					 byte 16r66, byte 16r3F, byte 16r00, byte 16r00, byte 16r00};
	
	sys->fprint(stdout, "LRC of:%s\n", hexdump(b));
	sys->fprint(stdout, "LRC ==\t%0X\n", int exactus->lrc(b));
	
	sys->fprint(stdout, "IEEE-734: 0x11223344, decimal: 1.2795344104949228e-28\n");
	b = array[] of {byte 16r11, byte 16r22, byte 16r33, byte 16r44};
	x := array[1] of real;
	math->import_real32(b, x);
	sys->fprint(stdout, "  result: %g\n", x[0]);
	sys->fprint(stdout, " ieee754: %g\n", exactus->ieee754(b));
}

testnetwork(p: ref Exactus->Port)
{
	m := ref TMmsg.Readholdingregisters(Modbus->FrameRTU, 1, -1, 16r1305, 16r0009);
	test(p, m.pack(), "read (0x1305) Serial number (9 ASCII bytes)");
	purge(p);
}

test(p: ref Port,b: array of byte, s: string)
{
	if(p != nil) {
		sys->fprint(stdout, "\nTest: %s\n", s);
		start := sys->millisec();
		n := p.write(b);
		stop := sys->millisec();
		sys->fprint(stdout, "TX -> %s\t(%d, %d)\n", hexdump(b), n, stop-start);

		(r, err) := p.readreply(500);
		if(r != nil) {
			buf := r.pack();
			sys->fprint(stdout, "reply: %s\n", hexdump(buf));
		} else {
			p.rdlock.obtain();
			sys->fprint(stdout, "RX <- %s\n", hexdump(p.avail));
			p.rdlock.release();
		}
	}
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
