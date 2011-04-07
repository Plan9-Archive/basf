# BASF Exactus(R) Pyromemeter
#
# Copyright (C) 2011, Corpus Callosum Corporation.  All Rights Reserved.

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
	
	Texactus,
	Rexactus,
	Tmodbus,
	Rmodbus,
	Tmax:	con 100+iota;
	
	# Exactus Data Messages
	ERtemperature,
	ERcurrent,
	ERdual,
	ERdevice,
	ERstx,
	ERack,
	ERnak,
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

		path:	string;
		ctl:	ref Sys->FD;
		data:	ref Sys->FD;
		
		rdlock: ref Lock->Semaphore;
		wrlock: ref Lock->Semaphore;		
		
		# input reader
		avail:	array of byte;
		pid:	int;
		
		write: fn(p: self ref Port, b: array of byte): int;
		
		getreply:	fn(p: self ref Port): (ref ERmsg, array of byte, string);
		readreply:	fn(p: self ref Port, ms: int): (ref ERmsg, array of byte, string);
	};
	
	ETmsg: adt {
		pick {
		Readerror =>
			error:	string;
		ExactusMsg =>
			rtype:	int;
			data:	array of byte;
		ModbusMsg =>
			addr:	byte;
			msg:	ref Modbus->TMmsg;
			crc:	int;
		}
		
		packedsize:	fn(nil: self ref ETmsg): int;
		pack:	fn(nil: self ref ETmsg): array of byte;
		
		dtype:	fn(nil: self ref ETmsg): (array of byte, ref Modbus->TMmsg);
	};
	
	ERmsg: adt {
		pick {
		Readerror =>
			error:	string;
		ExactusMsg =>
			rtype:	int;
			data: array of byte;
		ModbusMsg =>
			msg:	ref Modbus->RMmsg;
		}
		
		packedsize:	fn(nil: self ref ERmsg): int;
		pack:	fn(nil: self ref ERmsg): array of byte;
		
		dtype:	fn(nil: self ref ERmsg): (array of byte, ref Modbus->RMmsg);
	};
	
	init:	fn();
	
	open:	fn(path: string): ref Exactus->Port;
	close:		fn(p: ref Port): ref Sys->Connection;
	
	lrc:	fn(buf: array of byte): byte;
	ieee754:	fn(b: array of byte): real;
};
