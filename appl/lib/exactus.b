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
	if(p != nil && p.data != nil && b != nil && len b > 0) {
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
			(o, m) := Emsg.unpack(p.avail);
			if(m != nil)
				r = ref ERmsg.ExactusMsg(m);
			p.avail = p.avail[o:];
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

Emsg.temperature(m: self ref Emsg): real
{
	if(m != nil) {
		pick p := m {
		Temperature =>
			return p.degrees;
		}
	}
	return Math->NaN;
}

Emsg.current(m: self ref Emsg): real
{
	if(m != nil) {
		pick p := m {
		Current =>
			return p.amps;
		}
	}
	return Math->NaN;
}

Emsg.dual(m: self ref Emsg): (real, real)
{
	d, a : real;
	d = a = Math->NaN;
	if(m != nil) {
		pick p := m {
		Dual =>
			d = p.degrees;
			a = p.amps;
		}
	}
	return (d, a);
}

Emsg.device(m: self ref Emsg): (real, real)
{
	e, c : real;
	e = c = Math->NaN;
	if(m != nil) {
		pick p := m {
		Device =>
			e = p.edegrees;
			c = p.cdegrees;
		}
	}
	return (e, c);
}

Emsg.acknowledge(m: self ref Emsg): byte
{
	b : byte;
	if(m != nil) {
		pick p := m {
		Acknowledge =>
			b = p.c;
		}
	}
	return b;
}

Emsg.unpack(b: array of byte): (int, ref Emsg)
{
	i := 0;
	m : ref Emsg;
	if(b != nil && len b > 0) {
		nb : array of byte;
		case int b[0] {
		int ERtemperature =>
			(i, nb) = deescape(b[1:], 4);
			if(nb != nil)
				m = ref Emsg.Temperature(ieee754(nb));
		int ERcurrent =>
			(i, nb) = deescape(b[1:], 4);
			if(nb != nil)
				m = ref Emsg.Current(ieee754(nb));
		int ERdual =>
			(i, nb) = deescape(b[1:], 8);
			if(nb != nil)
				m = ref Emsg.Dual(ieee754(nb[0:4]), ieee754(nb[4:8]));
		int ERdevice =>
			(i, nb) = deescape(b[1:], 8);
			if(nb != nil)
				m = ref Emsg.Device(ieee754(nb[0:4]), ieee754(nb[4:8]));
		int ERreserved =>
			sys->fprint(stderr, "Reserved message attempt: %s\n", hexdump(b));
			i = len b;
		int ACK or int NAK =>
			m = ref Emsg.Acknowledge(b[0]);
			i++;
		}
	}
	return (i, m);
}

escape(buf: array of byte): array of byte
{
	nb : array of byte;
	if(buf != nil) {
		nb = array[len buf] of byte;
		j := 0;
		for(i:=0; i<len buf; i++) {
			b := buf[i];
			if(ERescape <= b && b <= ERreserved) {
				tmp := array[len nb +1] of byte;
				tmp[0:] = nb[0:len nb];
				nb = tmp;
				nb[j++] = ERescape;
			}
			nb[j++] = b;
		}
	}
	return nb;
}

deescape(buf: array of byte, n: int): (int, array of byte)
{
	nb : array of byte;
	i := 0;
	m := len buf;
	if(buf != nil && m >= n) {
		valid := 1;
		tmp := array[n] of { * => byte 0 };
		j := 0;
		for(i=0; i<m; i++) {
			b := buf[i];
			if(b == ERescape) {
				i++;
				if(i>=m) {
					valid = 0;
					break;
				}
				b = buf[i];
			}
			tmp[j++] = b;
		}
		if(valid)
			nb = tmp[0:j];
	}
	return (i, nb);
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

ETmsg.dtype(t: self ref ETmsg): (ref Emsg, ref Modbus->TMmsg)
{
	e : ref Emsg;
	m : ref Modbus->TMmsg;
	if(t != nil)
		pick x := t {
		ExactusMsg => e = x.msg;
		ModbusMsg => m = x.msg;
		}
	return (e, m);
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

ERmsg.dtype(t: self ref ERmsg): (ref Emsg, ref Modbus->RMmsg)
{
	e : ref Emsg;
	m : ref Modbus->RMmsg;
	if(t != nil)
		pick x := t {
		ExactusMsg => e = x.msg;
		ModbusMsg => m = x.msg;
		}
	return (e, m);
}

Trecord.pack(t: self ref Trecord): array of byte
{
	b := array[36] of { * => byte 0};
	v : array of byte;
	# timestamp
	v = i2b(int t.time);
	b[0] = v[0];
	b[1] = v[1];
	b[2] = v[2];
	b[3] = v[3];
	# temperature 0
	v = lpackr(t.temp0);
	b[4] = v[0];
	b[5] = v[1];
	b[6] = v[2];
	b[7] = v[3];
	if(0) {						# no need to archive the rest
	# temperature 1
	v = lpackr(t.temp1);
	b[8] = v[0];
	b[9] = v[1];
	b[10] = v[2];
	b[11] = v[3];
	# temperatue 2
	v = lpackr(t.temp2);
	b[12] = v[0];
	b[13] = v[1];
	b[14] = v[2];
	b[15] = v[3];
	# current 1
	v = lpackr(t.current1);
	b[16] = v[0];
	b[17] = v[1];
	b[18] = v[2];
	b[19] = v[3];
	# current 2
	v = lpackr(t.current2);
	b[20] = v[0];
	b[21] = v[1];
	b[22] = v[2];
	b[23] = v[3];
	# electronics temp 1
	v = lpackr(t.etemp1);
	b[24] = v[0];
	b[25] = v[1];
	b[26] = v[2];
	b[27] = v[3];
	# electronics temp 2
	v = lpackr(t.etemp2);
	b[28] = v[0];
	b[29] = v[1];
	b[30] = v[2];
	b[31] = v[3];
	# emissivity
	v = lpackr(t.emissivity);
	b[32] = v[0];
	b[33] = v[1];
	b[34] = v[2];
	b[35] = v[3];
	}
	return b;
}

lpackr(r: real): array of byte
{
	b := array[4] of byte;
	x := array[1] of real;
	x[0] = r;
	math->export_real32(b, x);
	return swapendian(b);
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
	switchmodbus(p);
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

readreply(p: ref Port, ms: int): (ref ERmsg, array of byte, string)
{
	return p.readreply(ms);
}

write(p: ref Port, b: array of byte): int
{
	return p.write(b);
}


switchexactus(p: ref Port, addr: int)
{
	m := ref TMmsg.Writecoil(Modbus->FrameRTU, addr, -1, 16r0013, 16r0000);
	p.write(m.pack());
}

switchmodbus(p: ref Port)
{
	if(p != nil) {
		b := array[] of {
			byte 16r02, byte 16r4d, byte 16r4d, byte 16r03,
		};
		p.write(b);
	}
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
	if(len b >= 4) {
		x := array[1] of real;
		math->import_real32(b[0:4], x);
		r = x[0];
	}
	return r;
}

# support fn
swapendian(b: array of byte): array of byte
{
	nb : array of byte;
	if(len b >= 4) {
		nb = array[4] of byte;
		nb[0] = b[3];
		nb[1] = b[2];
		nb[2] = b[1];
		nb[3] = b[0];
	}
	return nb;
}

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
