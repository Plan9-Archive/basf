implement Exactus;

include "sys.m";
include "dial.m";
include "math.m";
include "lock.m";
include "string.m";

include "modbus.m";
include "exactus.m";

sys: Sys;
dial: Dial;
math: Math;
str: String;
lock: Lock;
	Semaphore: import lock;

modbus: Modbus;
	RMmsg, TMmsg: import modbus;

stderr: ref Sys->FD;
debug := 0;

init()
{
	sys = load Sys Sys->PATH;
	dial = load Dial Dial->PATH;
	math = load Math Math->PATH;
	str = load String String->PATH;
	lock = load Lock Lock->PATH;
	if(lock == nil)
		raise "fail: Couldn't load lock module";
	lock->init();

	modbus = load Modbus Modbus->PATH;
	modbus->init();
	
	stderr = sys->fildes(2);
}

Port.write(p: self ref Port, b: array of byte): int
{
	r := 0;
	if(b != nil && len b > 0) {
		p.wrlock.obtain();
		if(p.mode == ModeModbus)
			sys->sleep(5);	# more than 3.5 char times a byte at 115.2kb
		r = sys->write(p.data, b, len b);
		p.wrlock.release();
	}
	return r;
}

Port.getreply(p: self ref Port): (ref ERmsg, array of byte, string)
{
	r : ref ERmsg;
	b : array of byte;
	err : string;
	
	if(p==nil)
		return (r, b, "No valid port");
	
	p.rdlock.obtain();
	n := len p.avail;
	if(n > 0) {
		if(p.mode == Exactus->ModeExactus) {
		}
		if(p.mode == Exactus->ModeModbus) {
			if(n >= 4) {
				(o, m) := RMmsg.unpack(p.avail, Modbus->FrameRTU);
				if(m != nil) {
					pick x := m {
					Readerror =>
						err = x.error;
						r = ref ERmsg.Readerror(err);
					* =>
						r = ref ERmsg.ModbusMsg(m);
					}
					b = p.avail[0:o];
					p.avail = p.avail[o:];
				}
			}
		}
	}
	p.rdlock.release();
	
	return (r, b, err);
}

# read until timeout or result is returned
Port.readreply(p: self ref Port, ms: int): (ref ERmsg, array of byte, string)
{
	if(p == nil)
		return (nil, nil, "No valid port");
	
	limit := 60000;			# arbitrary maximum of 60s
	r : ref ERmsg;
	b : array of byte;
	err : string;
	for(start := sys->millisec(); sys->millisec() <= start+ms;) {
		(r, b, err) = p.getreply();
		if(r == nil) {
			if(limit--) {
				sys->sleep(5);
				continue;
			}
			break;
		} else
			break;
	}
	
	return (r, b, err);
}

ttag2type := array[] of {
tagof ETmsg.Readerror => 0,
tagof ETmsg.ExactusMsg => Texactus,
tagof ETmsg.ModbusMsg => Tmodbus,
};

ETmsg.packedsize(t: self ref ETmsg): int
{
	n := 0;
	pick x := t {
	ExactusMsg => n = 0;
	ModbusMsg => n = x.msg.packedsize();
	}
	return n;
}

ETmsg.pack(t: self ref ETmsg): array of byte
{
	b : array of byte;
	if(t != nil && t.packedsize()) {
		pick x := t {
		ExactusMsg => b = nil;
		ModbusMsg => b = x.msg.pack();
		}
	}
	return b;
}

ETmsg.dtype(t: self ref ETmsg): (array of byte, ref Modbus->TMmsg)
{
	b : array of byte;
	m : ref Modbus->TMmsg;
	pick x := t {
	ExactusMsg => b = x.data;
	ModbusMsg => m = x.msg;
	}
	return (b, m);
}


ERmsg.packedsize(t: self ref ERmsg): int
{
	n := 0;
	pick x := t {
	ExactusMsg => n = 0;
	ModbusMsg => n = x.msg.packedsize();
	}
	return n;
}

ERmsg.pack(t: self ref ERmsg): array of byte
{
	b : array of byte;
	if(t != nil && t.packedsize()) {
		pick x := t {
		ExactusMsg => b = nil;
		ModbusMsg => b = x.msg.pack();
		}
	}
	return b;
}

ERmsg.dtype(t: self ref ERmsg): (array of byte, ref Modbus->RMmsg)
{
	b : array of byte;
	m : ref Modbus->RMmsg;
	pick x := t {
	ExactusMsg => b = x.data;
	ModbusMsg => m = x.msg;
	}
	return (b, m);
}

open(path: string): ref Exactus->Port
{
	if(sys == nil) init();
	
	np := ref Port;
	np.mode = ModeModbus;
	np.path = path;
	np.rdlock = Semaphore.new();
	np.wrlock = Semaphore.new();
	np.avail = nil;
	np.pid = 0;
	
	openport(np);
	if(np.data != nil);
		reading(np);
	
	return np;
}

# prepare device port
openport(p: ref Port)
{
	if(p==nil) {
		raise "fail: port not initialized";
		return;
	}
	
	p.data = nil;
	p.ctl = nil;
	
	if(p.path != nil) {
		if(str->in('!', p.path)) {
			(ok, net) := sys->dial(p.path, nil);
			if(ok == -1) {
				raise "can't open "+p.path;
				return;
			}
			
			p.ctl = sys->open(net.dir+"/ctl", Sys->ORDWR);
			p.data = sys->open(net.dir+"/data", Sys->ORDWR);
		} else {
			p.ctl = sys->open(p.path+"ctl", Sys->ORDWR);
			p.data = sys->open(p.path, Sys->ORDWR);
			b := array[] of { byte "b115200" };
			sys->write(p.ctl, b, len b);
		}
	}
	if(p.ctl == nil || p.data == nil) {
		raise "fail: file does not exist";
		return;
	}
	
	b := array[] of {
		byte 16r02, byte 16r4d, byte 16r4d, byte 16r03,
	};
	p.write(b);
}

# shut down reader (if any)
close(p: ref Port): ref Sys->Connection
{
	if(p == nil)
		return nil;
	
	if(p.pid != 0){
		kill(p.pid);
		p.pid = 0;
	}
	if(p.data == nil)
		return nil;
	c := ref sys->Connection(p.data, p.ctl, nil);
	p.ctl = nil;
	p.data = nil;
	
	hangup := array[] of {byte "hangup"};
	sys->write(p.ctl, hangup, len hangup);
	
	return c;
}

reading(p: ref Port)
{
	if(p.pid == 0) {
		pidc := chan of int;
		spawn reader(p, pidc);
		p.pid = <-pidc;
	}
}

reader(p: ref Port, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	
	buf := array[1] of byte;
	for(;;) {
		while((n := sys->read(p.data, buf, len buf)) > 0) {
			p.rdlock.obtain();
			if(len p.avail < Sys->ATOMICIO) {
				na := array[len p.avail + n] of byte;
				if(len p.avail)
					na[0:] = p.avail[0:];
				na[len p.avail:] = buf[0:n];
				p.avail = na;
			}
			p.rdlock.release();
		}
		sys->fprint(stderr, "Exactus reader closed, trying again.\n");
		p.data = nil;
		p.ctl = nil;
		openport(p);
	}
}

# Exactus mode LRC Calculation
lrc(buf: array of byte): byte
{
	r := byte 0;
	n := len buf;
	if (n > 0)
		r = buf[0];
		
	for (i := 1; i < n; i++)
		r ^= buf[i];
	
	return r;
}

ieee754(b: array of byte): real
{
	r := Math->NaN;
	if(len b == 4) {
		x := array[1] of real;
		math->import_real32(b, x);
		r = x[0];
	}
	return r;
}

# support fn
b2i(b: array of byte): int
{
	i := 0;
	if(len b == 4) {
		i = int(b[0])<<0;
		i |= int(b[1])<<8;
		i |= int(b[2])<<16;
		i |= int(b[3])<<24;
	}
	return i;
}

i2b(i: int): array of byte
{
	b := array[4] of byte;
	b[0] = byte(i>>0);
	b[1] = byte(i>>8);
	b[2] = byte(i>>16);
	b[3] = byte(i>>24);
	return b;
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

# convenience
kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "kill") < 0)
		sys->print("zaber: can't kill %d: %r\n", pid);
}
