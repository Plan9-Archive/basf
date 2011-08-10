implement DumpBin;

include "sys.m";
include "draw.m";
include "arg.m";
include "lock.m";
include "string.m";

include "modbus.m";
include "exactus.m";

sys: Sys;
str: String;

exactus: Exactus;
	EPort, Emsg, ERmsg, Trecord: import exactus;

DumpBin: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

stdout, stderr: ref Sys->FD;
debug := 0;

outfile : string;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);
	str = load String String->PATH;

	exactus = load Exactus Exactus->PATH;
	exactus->init();
	
	all := 0;

	arg := load Arg Arg->PATH;
	arg->init(argv);
	arg->setusage(arg->progname() + " [-a] [-o file] [-] [file...]");
	while((c := arg->opt()) != 0)
		case c {
		'a' =>	all++;
		'o' => outfile = arg->earg();
		* => arg->usage();
		}

	args := arg->argv();
	if(args == nil)
		args = "-" :: nil;
	
	for(; args != nil; args = tl args){
		file := hd args;
		if(file != "-"){
			fd := sys->open(file, Sys->OREAD);
			if(fd == nil){
				sys->fprint(sys->fildes(2), "dumpbin: cannot open %s: %r\n", file);
				raise "fail:bad open";
			}
			dump(fd, all, file);
		} else
			dump(sys->fildes(0), all, "<stdin>");
	}
}

dump(fd: ref Sys->FD, all: int, file: string)
{
	buf := array[36] of byte;
	
	ofd := stdout;
	if(outfile != nil) {
		ofd = sys->create(outfile, sys->OWRITE, 8r664);
		if(ofd == nil)
			ofd = stderr;
	}
	
	while((n := sys->read(fd, buf, len buf)) > 0) {
		if(n < len buf)
			sys->fprint(sys->fildes(2), "dumpbin: last record too short: %d\n", n);
		(nil, t) := Trecord.unpack(buf);
		if(t != nil) {
			if(all) {
				sys->fprint(ofd,
				 "%d\t%.3f\t%.5e\t%.3f\t%.04f\t%.04f\t%.04f\t%.05f\t%.05f\n",
				 t.time, t.temp0, t.temp1, t.temp2, t.current1, t.current2,
				 t.etemp1, t.etemp2, t.emissivity);
			} else {
				sys->fprint(ofd, "%d\t%.3f\n", t.time, t.temp0);
			}
		} else
			sys->fprint(stderr, "error unpacking: %s\n", hexdump(buf));
	}
	if(n < 0) {
		sys->fprint(sys->fildes(2), "dumpbin: error reading %s: %r\n", file);
		raise "fail:read error";
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
