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
	Port, Emsg, ERmsg, Trecord: import exactus;

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
	
	# testdata();

	if(port != nil && skip == 0)
		testnetwork(port);
	
	if(port != nil)
		exactus->close(port);
}

purge(p: ref Port)
{
	p.rdlock.obtain();
	p.avail = nil;
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
	
	b = array[] of {byte 16r00, byte 16re0, byte 16r22, byte 16r44};
	sys->fprint(stdout, "Content demo:\n%s (651.5)\n", hexdump(b));
	sys->fprint(stdout, "\t%g\n", exactus->ieee754(b));
	b = array[] of {byte 16r44, byte 16r22, byte 16re0, byte 16r00};
	sys->fprint(stdout, "%s (%g)\n", hexdump(b), exactus->ieee754(b));
	b = exactus->swapendian(b);
	sys->fprint(stdout, "%s (%g)\n", hexdump(b), exactus->ieee754(b));
	b = exactus->swapendian(b);

	r := exactus->ieee754(b);
	x[0] = r;
	b = array[4] of { * => byte 0 };
	math->export_real32(b, x);
	sys->fprint(stdout, "real cmp: %g =? %g\n", r, x[0]);
	
	sys->fprint(stdout, "Test Trecord: 0, 651.5\n");
	t := ref Exactus->Trecord(0, 651.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
	sys->fprint(stdout, "%s\n", hexdump(t.pack()));
	sys->fprint(stdout, "Test Trecord: 200, 651.25\n");
	t = ref Exactus->Trecord(200, 651.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
	sys->fprint(stdout, "%s\n", hexdump(t.pack()));
	
	sys->fprint(stdout, "Test Exactus temperature: 674.05 C\n");
	b = array[] of {byte 16r81, byte 16r44, byte 16r28, byte 16r80, byte 16r83, byte 0};
	sys->fprint(stderr, "%s\n", hexdump(b));
	(nil, tb) := exactus->deescape(Exactus->ERescape, b[1:], 4);
	sys->fprint(stderr, "%s\n", hexdump(tb));
	sys->fprint(stderr, "%s\n", hexdump(exactus->escape(tb)));
	sys->fprint(stdout, "\t%g\n", exactus->ieee754(tb));
	
	(n, m) := Emsg.unpack(b);
	sys->fprint(stdout, "Temperature Emsg.unpack(): %s\n", hexdump(b));
	sys->fprint(stderr, "\tdegrees: %g\n", m.temperature());

	b = array[] of {byte 16r82, byte 16r2C, byte 16r5A, byte 16r4E, byte 16r12};
	(n, m) = Emsg.unpack(b);
	sys->fprint(stdout, "Current Emsg.unpack(): %s\n", hexdump(b));
	sys->fprint(stderr, "\tamps: %g\n", m.current());
	
	b = array[] of {byte 16r83, byte 16r44, byte 16r28, byte 16r4D, byte 16r71,
					byte 16r35, byte 16r75, byte 16rF9, byte 16r08};
	(n, m) = Emsg.unpack(b);
	sys->fprint(stdout, "Dual Emsg.unpack(): %s\n", hexdump(b));
	(d, a) := m.dual();
	sys->fprint(stderr, "\tdegrees: %g\n", d);
	sys->fprint(stderr, "\tamps: %g\n", a);

	b = array[] of {byte 16r84, byte 16r41, byte 16rE3, byte 16r33, byte 16r33,
					byte 16r41, byte 16rFC, byte 16r00, byte 16r00};
	(n, m) = Emsg.unpack(b);
	sys->fprint(stdout, "Device Emsg.unpack(): %s\n", hexdump(b));
	(d, a) = m.device();
	sys->fprint(stderr, "\telectronics: %g\n", d);
	sys->fprint(stderr, "\tchassis: %g\n", a);
	
	b = array[] of {Exactus->ACK, byte 16r83, byte 16r44, byte 16r28, byte 16r4D,
					byte 16r71, byte 16r35, byte 16r75, byte 16rF9, byte 16r08};
	(n, m) = Emsg.unpack(b);
	sys->fprint(stdout, "Acknowledge Emsg.unpack(): %s\n", hexdump(b));
	sys->fprint(stdout, "\tn: %d %d\n", n, len b);
	if(n) {
		b = b[n:];
	}
	(n, m) = Emsg.unpack(b);
	sys->fprint(stdout, " remaining: %s\n", hexdump(b));
	(d, a) = m.dual();
	sys->fprint(stdout, "\tn: %.3f %.5e\n", d, a);
}

testnetwork(p: ref Exactus->Port)
{
	exactus->modbusmode(p);
	(r, bytes, err) := exactus->readreply(p, 125);
	if(err != nil)
		sys->fprint(stderr, "Read error: %s\n", err);
	if(bytes != nil)
		sys->fprint(stderr, "RX <- %s\n", hexdump(bytes));
	purge(p);

	m := ref TMmsg.Readholdingregisters(Modbus->FrameRTU, 1, -1, 16r1305, 16r0009);
	r = test(p, m.pack(), "read (0x1305) Serial number (9 ASCII bytes)");
	purge(p);
	(nil, mt) := r.dtype();
	if(mt != nil) {
		sys->fprint(stdout, "Text: %s\n", mt.text());
		pick x := mt {
		Readholdingregisters =>
			d := x.data;
			n := len d;
			sys->fprint(stdout, "\t%d %d\n%s\n", n, int d[1], hexdump(d));
			s := array[n] of { * => byte 0};
			j := 0;
			for(i := 0; i < n; i=i+2) {
				c := d[i+1];
				if(c == byte 0 || c > byte 16r7f)
					break;
				s[j++] = c;
			}
			sys->fprint(stdout, "\t%s\n", string s);
		}
	}
	
	m = ref TMmsg.Readholdingregisters(Modbus->FrameRTU, 1, -1, 16r0000, 16r0002);
	r = test(port, m.pack(), "read (0x0000) channel 1 temperature");
	purge(port);
	(nil, mt) = r.dtype();
	if(mt != nil) {
		sys->fprint(stdout, "Text: %s\n", mt.text());
		sys->fprint(stdout, "\t%g\n", mdata(mt, 0));
	}

	sys->fprint(stdout, "\nTesting Modbus Mode:\n");
	C := 20;
	start := sys->millisec();
	for(i := 0; i < C; i++) {
		m = ref TMmsg.Readholdingregisters(Modbus->FrameRTU, 1, -1, 16r0004, 16r0004);
		port.write(m.pack());
		(r, bytes, err) = port.readreply(125);
		if(err != nil)
			sys->fprint(stderr, "Read error: %s\n", err);
		if(bytes != nil)
			sys->fprint(stderr, "RX <- %s\n", hexdump(bytes));
		ms := sys->millisec();
		(nil, mt) = r.dtype();
		if(mt != nil)
			sys->fprint(stdout, "%04d: %0.2f°C\t%5g Amps\n", ms-start,
						mdata(mt, 4), mdata(mt, 0));
	}
	end := sys->millisec();
	sys->fprint(stderr, "%d modbus reads in %dms (%g ms/r)\n", C, end - start,
				real(end-start)/real C);
	
	m = ref TMmsg.Readholdingregisters(Modbus->FrameRTU, 1, -1, 16r1011, 16r0001);
	r = test(port, m.pack(), "read (0x1011) sample rate");

	port.rdlock.obtain();
	sys->fprint(stderr, "Remaining data: %s\n", hexdump(port.avail));
	port.rdlock.release();

	texactusmode(p);
}

texactusmode(p: ref Exactus->Port)
{
	sys->fprint(stdout, "\nTesting Exactus Mode:\n");
	exactus->exactusmode(p, 1);
	(r, bytes, err) := exactus->readreply(p, 125);
	if(err != nil)
		sys->fprint(stderr, "Read error: %s\n", err);
	if(bytes != nil)
		sys->fprint(stderr, "RX <- %s\n", hexdump(bytes));
	(e, nil) := r.dtype();
	if(e != nil)
		sys->fprint(stderr, "\t%s\n", e.text());

	start := sys->millisec();
	for(i := 0; i < 100; i++) {
		(r, bytes, err) = exactus->readreply(p, 125);
		if(r != nil || bytes != nil || err != nil) {
			sys->fprint(stderr, "%3d: ", i);
			if(bytes != nil)
				sys->fprint(stderr, "\t %2X %s", int bytes[0], hexdump(bytes[1:]));			
			if(err != nil)
				sys->fprint(stderr, "\t%s", err);
			if(r != nil)
				(e, nil) = r.dtype();
				if(e != nil)
					sys->fprint(stderr, "\t%s", e.text());
			sys->fprint(stderr, "\n");
		}
	}
	end := sys->millisec();
	sys->fprint(stderr, "%d exactus reads in %dms (%g ms/r)\n", 100, end - start,
				real(end-start)/real 100);

	p.rdlock.obtain();
	if(p.avail != nil)
		sys->fprint(stderr, "Remaining data: %s\n", hexdump(p.avail));
	p.rdlock.release();

	exactus->modbusmode(p);
}

mdata(m: ref Modbus->RMmsg, n: int): real
{
	r : real;
	pick x := m {
	Readholdingregisters =>
		if(len x.data >= n+4)
			r = exactus->ieee754(x.data[n:n+4]);
	}
	return r;
}

test(p: ref Port, b: array of byte, s: string): ref ERmsg
{
	r : ref ERmsg;
	if(p != nil) {
		bytes : array of byte;
		err : string;
		
		sys->fprint(stdout, "\nTest: %s\n", s);
		start := sys->millisec();
		n := p.write(b);
		stop := sys->millisec();
		sys->fprint(stderr, "TX -> %s\t(%d, %d)\n", hexdump(b), n, stop-start);

		(r, bytes, err) = p.readreply(500);
		if(err != nil)
			sys->fprint(stderr, "Read error: %s\n", err);
		if(bytes != nil)
			sys->fprint(stderr, "RX <- %s\n", hexdump(bytes));
		if(r != nil) {
			buf := r.pack();
			sys->fprint(stderr, "reply: %s\n", hexdump(buf));
		}
	}
	return r;
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
