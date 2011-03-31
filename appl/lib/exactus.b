implement Exactus;

include "sys.m";
include "dial.m";
include "lock.m";
include "string.m";

include "exactus.m";

sys: Sys;
dial: Dial;
str: String;
lock: Lock;
	Semaphore: import lock;


Port.write(p: self ref Port, b: array of byte): int
{
	r := 0;
	p.wrlock.obtain();
	r = sys->write(p.data, b, len b);
	return r;
}

stderr: ref Sys->FD;

init()
{
	sys = load Sys Sys->PATH;
	dial = load Dial Dial->PATH;
	str = load String String->PATH;
	lock = load Lock Lock->PATH;
	if(lock == nil)
		raise "fail: Couldn't load lock module";
	lock->init();

	stderr = sys->fildes(2);
}

open(path: string): ref Exactus->Port
{
	if(sys == nil) init();
	
	np := ref Port;
	np.mode = ModeModbus;
	np.local = path;
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
	
	if(p.local != nil) {
		if(str->in('!', p.local)) {
			(ok, net) := sys->dial(p.local, nil);
			if(ok == -1) {
				raise "can't open "+p.local;
				return;
			}
			
			p.ctl = sys->open(net.dir+"/ctl", Sys->ORDWR);
			p.data = sys->open(net.dir+"/data", Sys->ORDWR);
		} else {
			p.ctl = sys->open(p.local+"ctl", Sys->ORDWR);
			p.data = sys->open(p.local, Sys->ORDWR);
			b := array[] of { byte "b115200" };
			sys->write(p.ctl, b, len b);
		}
	}
	if(p.ctl == nil || p.data == nil) {
		raise "fail: file does not exist";
		return;
	}
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
	return c;
}

getreply(p: ref Port, n: int): array of ref ERmsg
{
	if(p==nil || n <= 0)
		return nil;
	
	b : array of byte;
	p.rdlock.obtain();
	if(len p.avail != 0) {
		if((n*6) > len p.avail)
			n = len p.avail / 6;
		b = p.avail[0:(n*6)];
		p.avail = p.avail[(n*6):];
	}
	p.rdlock.release();
	
	a : array of ref ERmsg;
	if(len b) {
		a = array[n] of { * => ref ERmsg};
#		for(j:=0; j<n; j++) {
#			i := a[j];
#			i.id = int(b[(j*6)]);
#			i.cmd = int(b[(j*6)+1]);
#			i.data = b[(j*6)+2:(j*6)+6];
#		}
	}
	return a;
}

# read until timeout or result is returned
readreply(p: ref Port, ms: int): ref ERmsg
{
	if(p == nil)
		return nil;
	
	limit := 60000;			# arbitrary maximum of 60s
	r : ref ERmsg;
	for(start := sys->millisec(); sys->millisec() <= start+ms;) {
		a := getreply(p, 1);
		if(len a == 0) {
			if(limit--) {
				sys->sleep(1);
				continue;
			}
			break;
		}
		return a[0];
	}
	
	return r;
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
		sys->fprint(stderr, "reader closed\n");
		# error, try again
		p.data = nil;
		p.ctl = nil;
		openport(p);
	}
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

# convenience
kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "kill") < 0)
		sys->print("zaber: can't kill %d: %r\n", pid);
}
