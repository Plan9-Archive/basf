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
	
	ModeExactus,						# Exactus mode
	ModeModbus,							# Modbus mode
	ModeMax:	con iota;
	
	# Exactus Data Messages
	ERtemperature,
	ERcurrent,
	ERdual,
	ERdevice,
	Emax:	con 100+iota;
	
	# Exactus host to Pyrometer commands
	ECmodbus,
	ECversion,
	ECstop,
	ECstart,
	ECsetcal,
	ECmax:	con 48+iota;
	
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
	
	ERmsg: adt {
		mode: int;
	};
	
	init:	fn();
	
	open:	fn(path: string): ref Exactus->Port;
	close:		fn(p: ref Port): ref Sys->Connection;
	
	getreply:	fn(p: ref Port, n: int): array of ref ERmsg;
	readreply:	fn(p: ref Port, ms: int): ref ERmsg;
};
