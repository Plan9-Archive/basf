# BASF Exactus(R) Pyromemeter
#
# Copyright (C) 2011, Corpus Callosum Corporation.  All Rights Reserverd.

Exactus : module
{
	PATH:		con "/dis/lib/exactus.dis";

	STX:	con byte 16r02;
	ETX:	con byte 16r03;
	ACK:	con byte 16r06;
	DLE:	con byte 16r10;
	NAK:	con byte 16r15;
	
	Emode,							# Exactus mode
	Mmode:	con iota;				# Modbus mode
	
	# Exactus messages
	Tversion,
	Rversion,
	Tswitch,
	Rswitch,
	Tstart,
	Rstart,
	Tstop,
	Rstop,
	Tcalibrate,
	Rcalibrate,
	Tmodbus,
	Rmodbus,

	ERtemperature,
	ERcurrent,
	ERdual,
	ERambient,
	Emax:	con 100+iota;
	
	Emsg: adt {
		tag: int;
		pick {
		Modbus =>
			fid: int;
			data: array of byte;
		Switch or
		Version or
		Start or
		Stop =>
			fid: int;
		Calibration =>
			fid: int;
			factor: real;
		}
		
		unpack:	fn(a: array of byte): (int, ref Tmsg);
		pack:	fn(nil: self ref Tmsg): array of byte;
		packsize:	fn(nil:self ref Tmsg): int;
		mtype:	fn(nil: self ref Tmsg): int;
	};
	
	Rmsg: adt {
		tag: int;
		pick {
		Termerature =>
		Current =>
		Dual =>
		
		}
	};
	
	Port: adt
	{
		mode:	int;

		local:	string;
		ctl:	ref Sys->FD;
		data:	ref Sys->FD;
		
		rdlock: ref Lock->Semaphore;
		wrlock: ref Lock->Semaphore;		
		
		# input reader
		avail:	array of byte;
		pid:	int;
		
		write: fn(p: self ref Port, b: array of byte): int;
	};
	
	init:	fn();
	
	open:	fn(path: string): ref Exactus->Port;
	close:		fn(p: ref Port): ref Sys->Connection;
	
	getreply:	fn(p: ref Port, n: int): array of ref Instruction;
	readreply:	fn(p: ref Port, ms: int): ref Instruction;
	
	write:		fn(fd: ref Port, buf: array of byte, n: int): int;
	
	packcmd:	fn();
};
