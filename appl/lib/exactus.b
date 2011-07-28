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

DEBUG := 0;

# buffered reading channel
BUFSZ: con 1024;

SEBYTES : list of byte;
SMBYTES : list of byte;

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

	SEBYTES = STX :: ACK :: ERescape :: ERtemperature :: ERcurrent :: ERdual ::
		ERdevice :: ERreserved :: nil;
	SMBYTES =
		byte(Modbus->Treadcoils) :: byte(Modbus->Treaddiscreteinputs) ::
		byte(Modbus->Treadholdingregisters) :: byte(Modbus->Treadinputregisters) ::
		byte(Modbus->Twritecoil) :: byte(Modbus->Twriteregister) ::
		byte(Modbus->Treadexception) :: byte(Modbus->Tdiagnostics) ::
		byte(Modbus->Tcommeventcounter) :: byte(Modbus->Tcommeventlog) ::
		byte(Modbus->Twritecoils) :: byte(Modbus->Twriteregisters) ::
		byte(Modbus->Tslaveid) :: byte(Modbus->Treadfilerecord) ::
		byte(Modbus->Twritefilerecord) :: byte(Modbus->Tmaskwriteregister) ::
		byte(Modbus->Trwregisters) :: byte(Modbus->Treadfifo) :: 
		byte(Modbus->Tencapsulatedtransport) ::
		byte(Modbus->Terror + Modbus->Treadcoils) ::
		byte(Modbus->Terror + Modbus->Treaddiscreteinputs) ::
		byte(Modbus->Terror + Modbus->Treadholdingregisters) ::
		byte(Modbus->Terror + Modbus->Treadinputregisters) ::
		byte(Modbus->Terror + Modbus->Twritecoil) ::
		byte(Modbus->Terror + Modbus->Twriteregister) ::
		byte(Modbus->Terror + Modbus->Treadexception) ::
		byte(Modbus->Terror + Modbus->Tdiagnostics) ::
		byte(Modbus->Terror + Modbus->Tcommeventcounter) ::
		byte(Modbus->Terror + Modbus->Tcommeventlog) ::
		byte(Modbus->Terror + Modbus->Twritecoils) ::
		byte(Modbus->Terror + Modbus->Twriteregisters) ::
		byte(Modbus->Terror + Modbus->Tslaveid) ::
		byte(Modbus->Terror + Modbus->Treadfilerecord) ::
		byte(Modbus->Terror + Modbus->Twritefilerecord) ::
		byte(Modbus->Terror + Modbus->Tmaskwriteregister) ::
		byte(Modbus->Terror + Modbus->Trwregisters) ::
		byte(Modbus->Terror + Modbus->Treadfifo) ::
		byte(Modbus->Terror + Modbus->Tencapsulatedtransport) ::
	nil;
}

debug(f: int)
{
	DEBUG = f;
}

EPort.write(p: self ref EPort, b: array of byte): int
{
	r := 0;
	if(p != nil && p.data != nil && b != nil && len b > 0) {
		p.wrlock.obtain();
		if(p.mode == ModeModbus)
			sys->sleep(5);	# more than 3.5 char times a byte at 115.2kb
		fd := p.data;
		if(p.wdata != nil)
			fd = p.wdata;
		r = sys->write(fd, b, len b);
		if(DEBUG) sys->fprint(stderr, "TX -> %s\n", hexdump(b[0:r]));
		p.wrlock.release();
	}
	return r;
}

EPort.getreply(p: self ref EPort): (ref ERmsg, array of byte, string)
{
	r : ref ERmsg;
	b : array of byte;
	err : string;
	
	if(p==nil)
		return (r, b, "No valid port");
	
	p.rdlock.obtain();
	n := len p.buffer;
	if(n > 0) {
		case p.mode {
		ModeExactus =>
			(o, m) := Emsg.unpack(p.buffer);
			if(m != nil) {
				r = ref ERmsg.ExactusMsg(m);
				b = p.buffer[0:o];
				if(n > o)
					p.buffer = p.buffer[o:];
				else
					p.buffer = nil;
			}
		ModeModbus =>
			if(n >= 4) {
				(o, m) := RMmsg.unpack(p.buffer, Modbus->FrameRTU);
				if(m != nil) {
					pick x := m {
					Readerror =>
						err = x.error;
						r = ref ERmsg.Readerror(err);
					* =>
						r = ref ERmsg.ModbusMsg(m);
					}
					b = p.buffer[0:o];
					p.buffer = p.buffer[o:];
				}
			}
		}
	}
	p.rdlock.release();
	
	return (r, b, err);
}

# read until timeout or result is returned
EPort.readreply(p: self ref EPort, ms: int): (ref ERmsg, array of byte, string)
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

pbytes(p: ref EPort): array of byte
{
	b : array of byte;
	p.rdlock.obtain();
	b = p.buffer;
	p.rdlock.release();
	return b;
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

Emsg.text(m: self ref Emsg): string
{
	s := "";
	if(m != nil)
		pick x := m {
		Temperature =>
			s = sys->sprint("%.3f°C", x.degrees);
		Current =>
			s = sys->sprint("%3e Amps", x.amps);
		Dual =>
			s = sys->sprint("%.3f°C %3e Amps", x.degrees, x.amps);
		Device =>
			s = sys->sprint("electronics=%.3f°C chassis=%.3f°", x.edegrees, x.cdegrees);
		Version =>
			s = sys->sprint("mode=%2X appid=%2X version=%d.%d build=%d",
					int x.mode, int x.appid, x.vermajor, x.verminor, x.build);
		Acknowledge =>
			if(x.c == ACK)
				s += "ACK";
			else if(x.c == NAK)
				s += "NAK";
			else s+= "(invalid)";
		}
		
	return s;
}

Emsg.unpack(b: array of byte): (int, ref Emsg)
{
	i := 0;
	m : ref Emsg;
	if(b != nil && len b > 0) {
		nb : array of byte;
		case int b[0] {
		int ERtemperature =>
			(i, nb) = deescape(ERescape, b[1:], 4);
			if(nb != nil) {
				m = ref Emsg.Temperature(ieee754(nb));
				i++;
			}
		int ERcurrent =>
			(i, nb) = deescape(ERescape, b[1:], 4);
			if(nb != nil) {
				m = ref Emsg.Current(ieee754(nb));
				i++;
			}
		int ERdual =>
			(i, nb) = deescape(ERescape, b[1:], 8);
			if(nb != nil) {
				m = ref Emsg.Dual(ieee754(nb[0:4]), ieee754(nb[4:8]));
				i++;
			}
		int ERdevice =>
			(i, nb) = deescape(ERescape, b[1:], 8);
			if(nb != nil) {
				m = ref Emsg.Device(ieee754(nb[0:4]), ieee754(nb[4:8]));
				i++;
			}
		int ERreserved =>
			sys->fprint(stderr, "Reserved message attempt: %s\n", hexdump(b));
			i = len b;
		
		int STX =>
			(i, nb) = deescape(DLE, b[1:], 6);
			if(nb != nil && i+2 <= len b) {
				build := ((int nb[4]) << 8) | int nb[5];
				m = ref Emsg.Version(nb[0], nb[1], int nb[2], int nb[3], build);
				i += 2;
			}
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

deescape(esc: byte, buf: array of byte, n: int): (int, array of byte)
{
	nb : array of byte;
	i := 0;
	m := len buf;
	if(buf != nil && m >= n) {
		valid := 0;
		tmp := array[n] of { * => byte 0 };
		j := 0;
		for(i=0; i<m; i++) {
			b := buf[i];
			if(b == esc) {
				i++;
				if(i>=m) {
					break;
				}
				b = buf[i];
			}
			tmp[j++] = b;
			if(j == n) {
				valid = 1;
				break;
			}
		}
		if(valid) {
			nb = tmp[0:j];
			i++;
		}
		if(DEBUG>1){
			sys->fprint(stderr, "  deescape: %d (%s) (%s)\n", i, hexdump(buf), hexdump(nb));
		}
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

ERmsg.tostring(t: self ref ERmsg): string
{
	s : string;
	if(t != nil) {
		(e, m) := t.dtype();
		if(e != nil) {
			sys->fprint(stderr, "tostring unfinished\n");
		}
		if(m != nil) {
			pick x := m {
			Readholdingregisters =>
				d := x.data;
				n := len d;
				b := array[n] of { * => byte 0};
				j := 0;
				for(i := 0; i < n; i=i+2) {
					c := d[i+1];
					if(c == byte 0 || c > byte 16r7f)
						break;
					b[j++] = c;
				}
				s = string b;
			}
		}
	}
	return s;
}

Trecord.pack(t: self ref Trecord): array of byte
{
	b := array[36] of { * => byte 0};
	v : array of byte;
	# timestamp
	p32(b, 0, t.time);
	# temperature 0
	v = lpackr(t.temp0);
	b[4] = v[0];
	b[5] = v[1];
	b[6] = v[2];
	b[7] = v[3];
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
	
	return b;
}

Trecord.unpack(b: array of byte): (int, ref Trecord)
{
	if(len b < 36)
		return (0, nil);
	
	t := ref Trecord;
	t.time = g32(b, 0);
	t.temp0 = ieee754(swapendian(b[4:8]));
	t.temp1 = ieee754(swapendian(b[8:12]));
	t.temp2 = ieee754(swapendian(b[12:16]));
	t.current1 = ieee754(swapendian(b[16:20]));
	t.current2 = ieee754(swapendian(b[20:24]));
	t.etemp1 = ieee754(swapendian(b[24:28]));
	t.etemp2 = ieee754(swapendian(b[28:32]));
	t.emissivity = ieee754(swapendian(b[32:36]));
	
	return (36, t);
}

lpackr(r: real): array of byte
{
	b := array[4] of byte;
	x := array[1] of real;
	x[0] = r;
	math->export_real32(b, x);
	return swapendian(b);
}



open(path: string): ref Exactus->EPort
{
	if(sys == nil) init();
	
	np := ref EPort(ModeModbus, 1, 0.0, -1, path, nil, nil, nil,
					Semaphore.new(), Semaphore.new(), nil, nil, nil, 0);	
	openport(np);
	if(np.data != nil) {
		m := ref TMmsg.Readholdingregisters(Modbus->FrameRTU, 1, -1, 16r1011, 1);
		np.write(m.pack());
		(r, bytes, nil) := np.readreply(125);
		if(bytes != nil && DEBUG)
			dumpreceive(bytes);
		(nil, mt) := r.dtype();
		if(mt != nil) {
			pick x := mt {
			Readinputregisters or
			Readholdingregisters =>
				np.rate = g16(x.data, 0);
			}
		}
		reading(np);
	} else
		np = nil;
	return np;
}

# prepare device port
openport(p: ref EPort)
{
	if(p==nil) {
		raise "fail: port not initialized";
		return;
	}
		
	if(p.path != nil) {
		if(str->in('!', p.path)) {
			(ok, net) := sys->dial(p.path, nil);
			if(ok == -1) {
				sys->fprint(stderr, "can't open %s\n", p.path);
				return;
			}
			
			p.ctl = sys->open(net.dir+"/ctl", Sys->ORDWR);
			p.data = sys->open(net.dir+"/data", Sys->ORDWR);
		} else {
			p.ctl = sys->open(p.path+"ctl", Sys->ORDWR);
			p.data = sys->open(p.path, Sys->OREAD);
			p.wdata = sys->open(p.path, Sys->OWRITE);
			sys->seek(p.data, big 0, Sys->SEEKEND);
		}
	}
	if(p.ctl == nil || p.data == nil) {
		raise "fail: file does not exist";
		return;
	}
	modbusmode(p);
}

# shut down reader (if any)
close(p: ref EPort): ref Sys->Connection
{
	if(p == nil)
		return nil;

	if(p.data == nil)
		return nil;
	
	modbusmode(p);
	hangup := array[] of {byte "hangup"};
	sys->write(p.ctl, hangup, len hangup);
	c := ref sys->Connection(p.data, p.ctl, nil);
	p.ctl = nil;
	p.data = nil;
	p.wdata = nil;
	
	for(; p.pids != nil; p.pids = tl p.pids)
		kill(hd p.pids);
	
	return c;
}

readreply(p: ref EPort, ms: int): (ref ERmsg, array of byte, string)
{
	return p.readreply(ms);
}

write(p: ref EPort, b: array of byte): int
{
	return p.write(b);
}

flushreader(p: ref EPort, ms: int)
{
	for(start := sys->millisec(); sys->millisec() <= start+ms;) {
		if(pbytes(p) != nil) {
			p.rdlock.obtain();
			p.buffer = nil;
			p.rdlock.release();
		} else
			sys->sleep(5);
	}
}

exactusmode(p: ref EPort)
{
	if(p != nil) {
		# force temperature only
		m := ref TMmsg.Writeregister(Modbus->FrameRTU, p.maddr, -1, 16r1000, 16r0011);
		p.write(m.pack());
		(r, bytes, err) := p.readreply(1000);
		if(DEBUG) {
			if(err != nil)
				sys->fprint(stderr, "Exactus mode error (%s)\n", err);			
			if(bytes != nil)
				dumpreceive(bytes);
		}

		p.rdlock.obtain();
		m = ref TMmsg.Writecoil(Modbus->FrameRTU, p.maddr, -1, 16r0013, 16r0000);
		p.write(m.pack());
		p.buffer = nil;
		p.mode = ModeExactus;
		p.rdlock.release();
		flushreader(p, 250);

		# grab version
		b := array[] of {STX, byte 16r56, byte 16r56, ETX};
		p.write(b);
		(r, bytes, err) = p.readreply(1000);
		if(DEBUG) {
			if(err != nil)
				sys->fprint(stderr, "Exactus mode error (%s)\n", err);			
			if(bytes != nil)
				dumpreceive(bytes);
		}
		(e, nil) := r.dtype();
		if(e != nil && DEBUG)
			sys->fprint(stderr, "Version: %s (%s)\n", e.text(), hexdump(b));
			
		# start converting
		b = array[] of {STX, byte 16r31, byte 16r31, ETX};
		p.write(b);
		(r, bytes, err) = p.readreply(125);
		if(err != nil)
			sys->fprint(stderr, "Read error: %s\n", err);
		if(bytes != nil && DEBUG)
			dumpreceive(bytes);
		(e, nil) = r.dtype();
		if(e != nil && DEBUG)
			sys->fprint(stderr, "Start conversions: %s\n", e.text());
	}
}

modbusmode(p: ref EPort)
{
	if(p != nil) {
		e : ref Emsg;
		# stopconversion
		b := array[] of {Exactus->STX, byte 16r30, byte 16r30, Exactus->ETX};
		p.write(b);
		if(DEBUG)
			sys->fprint(stderr, "Stop conversions:\n");
		(r, bytes, err) := p.readreply(125);
		if(err != nil)
			sys->fprint(stderr, "Read error: %s\n", err);
		if(DEBUG) {
			if(bytes != nil)
				dumpreceive(bytes);
			(e, nil) = r.dtype();
			if(e != nil)
				sys->fprint(stderr, "\t%s\n", e.text());
		}

		b = array[] of {STX, byte 16r4d, byte 16r4d, ETX};
		p.write(b);
		(r, bytes, err) = p.readreply(125);
		if(err != nil)
			sys->fprint(stderr, "Read error: %s\n", err);
		if(DEBUG) {
			if(bytes != nil)
				dumpreceive(bytes);
			(e, nil) = r.dtype();
			if(e != nil)
				sys->fprint(stderr, "Enter Modbus mode: %s\n", e.text());
		}
		p.rdlock.obtain();
		p.buffer = nil;
		p.mode = ModeModbus;
		p.rdlock.release();
		flushreader(p, 125);
	}
}

reading(p: ref EPort)
{
	if(p.pids == nil)
		spawn reader(p);
}

ismember(b: byte, l: list of byte): int
{
	for(; l != nil; l = tl l)
		if(b == hd l)
			return 1;
	return 0;
}

ms := 0;
reader(p: ref EPort)
{
	p.pids = sys->pctl(0, nil) :: p.pids;
	
	c := chan[BUFSZ] of byte;
	e := chan of int;
	spawn bytereader(p, c, e);
		
	for(;;) alt {
	b := <- c =>
		p.rdlock.obtain();
		n := len p.buffer;
		if(n < Sys->ATOMICIO) {
			if(n == 0) {
				p.ms = ms;		# used in Trecord, track first byte
				l : list of byte;
				if(p.mode == ModeModbus)
					l = SMBYTES;
				else
					l = SEBYTES;
				if(!ismember(b, l)) {
					if(DEBUG)
						sys->fprint(stderr, "Frame error (invalid start byte): %2X\n", int b);
					p.rdlock.release();
					continue;
				}
			}
			na := array[n + 1] of byte;
			if(n)
				na[0:] = p.buffer[0:n];
			na[n] = b;
			if(p.mode == ModeExactus && p.tchan != nil) {
				(i, m) := Emsg.unpack(na);
				if(m != nil) {
					t := ref Trecord(p.ms, 0.0, 0.0, 0.0, 0.0, 0.0,
									0.0, 0.0, 1.0);
					pick x := m {
					Temperature =>
						t.temp0 = x.degrees;
						p.temp = x.degrees;
					Current =>
						t.current1 = x.amps;
					Dual =>
						t.temp0 = x.degrees;
						p.temp = x.degrees;
						t.current1 = x.amps;
					Device =>
						t.etemp1 =x.edegrees;
						t.etemp2 = x.cdegrees;
					* =>
						t = nil;
					}
					
					if(t != nil) {
						p.tchan <-= t;
						if(n > i)
							na = na[i:];
						else
							na = nil;
					}
				}
			}
			p.buffer = na;
		}
		p.rdlock.release();
	<-e =>
		if(DEBUG)
			sys->fprint(stderr, "Exactus reader closed, trying again.\n");
		p.data = nil;
		p.wdata = nil;
		p.ctl = nil;
		openport(p);
		spawn bytereader(p, c, e);
	}
}

bytereader(p: ref EPort, c: chan of byte, e: chan of int)
{
	p.pids = sys->pctl(0, nil) :: p.pids;
	buf := array[1] of byte;
	while(sys->read(p.data, buf, len buf) > 0) {
		ms = sys->millisec();
		c <-= buf[0];
	}
	e <-= 0;
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

graphrate(p: ref EPort): int
{
	if(p == nil)
		return -1;
	
	if(p.rate == -1) {
		change := 0;
		if(p.mode == ModeExactus) {
			change = 1;
			modbusmode(p);
			p.readreply(125);		# throw it away
		}
		
		m := ref TMmsg.Readholdingregisters(Modbus->FrameRTU, 1, -1, 16r1011, 1);
		p.write(m.pack());
		(r, bytes, nil) := p.readreply(125);
		if(bytes != nil && DEBUG)
			dumpreceive(bytes);
		(nil, mt) := r.dtype();
		if(mt != nil) {
			pick x := mt {
			Readinputregisters or
			Readholdingregisters =>
				p.rate = g16(x.data, 0);
			}
		}
		
		if(change) {
			exactusmode(p);
		}
	}
	
	return p.rate;
}

set_graphrate(p: ref EPort, rate: int)
{
	if(p == nil)
		return;

	change := 0;
	if(p.mode == ModeExactus) {
		change = 1;
		modbusmode(p);
		p.readreply(125);		# throw it away
	}

	m := ref TMmsg.Writeregister(Modbus->FrameRTU, p.maddr, -1, 16r1011, rate);
	p.write(m.pack());
	(r, bytes, err) := p.readreply(125);
	if(bytes != nil && DEBUG)
		dumpreceive(bytes);
	if(r != nil && err == nil)
		p.rate = rate;
	
	if(change)
		exactusmode(p);
}

serialnumber(p: ref EPort): string
{
	if(p == nil)
		return nil;
	
	change := 0;
	if(p.mode == ModeExactus) {
		change = 1;
		modbusmode(p);
		p.readreply(125);		# throw away
	}

	s := "";
	m := ref TMmsg.Readholdingregisters(Modbus->FrameRTU, p.maddr, -1, 16r1305, 16r0009);
	p.write(m.pack());
	(r, bytes, nil) := p.readreply(125);
	if(bytes != nil && DEBUG)
		dumpreceive(bytes);
	if(r != nil)
		s = r.tostring();

	if(change)
		exactusmode(p);
	
	return s;
}

temperature(p: ref EPort): real
{
	if(p == nil)
		return -1.0;
	
	r : ref ERmsg;
	if(p.mode == ModeModbus) {
		bytes: array of byte;
		m := ref TMmsg.Readholdingregisters(Modbus->FrameRTU, p.maddr, -1,
					16r0000, 16r0002);
		p.write(m.pack());
		(r, bytes, nil) = p.readreply(125);
		if(bytes != nil && DEBUG)
			dumpreceive(bytes);
		if(r != nil) {
			(nil, mt) := r.dtype();
			if(mt != nil)
				pick x := mt {
				Readholdingregisters =>
					if(len x.data >= 4)
						p.temp = ieee754(x.data[0:4]);
				}
		}
	}
	
	if(p.mode == ModeExactus && p.tchan == nil) {
		do {
			(r, nil, nil) = p.readreply(125);
			if(r != nil) {
				(m, nil) := r.dtype();
				if(m != nil) {
					pick x := m {
					Temperature =>
						p.temp = x.degrees;
					}
				}
			}
		} while(r != nil);
	}
		
	return p.temp;
}

# support fn
dumpreceive(bytes: array of byte)
{
	sys->fprint(stderr, "RX <- %s\n", hexdump(bytes));
}

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
		sys->fprint(stderr, "exactus: can't kill %d: %r\n", pid);
}


p16(a: array of byte, o: int, v: int): int
{
	a[o] = byte v;
	a[o+1] = byte (v>>8);
	return o+BIT16SZ;
}

g16(f: array of byte, i: int): int
{
	return ((int f[i]) << 8) | int f[i+1];
}

g32(f: array of byte, i: int): int
{
	return (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
}

p32(a: array of byte, o: int, v: int): int
{
	a[o] = byte v;
	a[o+1] = byte (v>>8);
	a[o+2] = byte (v>>16);
	a[o+3] = byte (v>>24);
	return o+BIT32SZ;
}
