# BASF Exactus(R) Pyromemeter
#
# Copyright (C) 2011, Corpus Callosum Corporation.  All Rights Reserved.

Exactus : module
{
	PATH:		con "/dis/lib/exactus.dis";

	BIT8SZ:	con 1;
	BIT16SZ:	con 2;
	BIT32SZ:	con 4;
	BIT64SZ:	con 8;

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
	ERescape,
	ERtemperature,
	ERcurrent,
	ERdual,
	ERdevice,
	ERreserved:	con byte (16r80+iota);
	
	# Exactus host to Pyrometer commands
	ECmodbus,
	ECversion,
	ECstop,
	ECstart,
	ECsetcal,
	ECmax:	con 48+iota;
		
	EPort: adt
	{
		mode:	int;

		maddr:	int;					# Modbus address
		
		path:	string;
		ctl:	ref Sys->FD;
		data:	ref Sys->FD;
		
		rdlock: ref Lock->Semaphore;
		wrlock: ref Lock->Semaphore;		
		
		# bytes from reader
		avail:	array of byte;
		pids:	list of int;
		tchan:	chan of ref Exactus->Trecord;
		
		write: fn(p: self ref EPort, b: array of byte): int;
		
		getreply:	fn(p: self ref EPort): (ref ERmsg, array of byte, string);
		readreply:	fn(p: self ref EPort, ms: int): (ref ERmsg, array of byte, string);
	};
	
	Emsg: adt {
		pick {
		Temperature =>
			degrees:	real;
		Current =>
			amps:	real;
		Dual =>
			degrees:	real;
			amps:	real;
		Device =>
			edegrees:	real;
			cdegrees:	real;
		Version =>
			mode:	byte;
			appid:	byte;
			vermajor:	int;
			verminor:	int;
			build:	int;
		Acknowledge =>
			c:	byte;
		}
		
		temperature:	fn(m: self ref Emsg): real;
		current:		fn(m: self ref Emsg): real;
		dual:			fn(m: self ref Emsg): (real, real);
		device:			fn(m: self ref Emsg): (real, real);
		acknowledge:	fn(m: self ref Emsg): byte;
		
		unpack: fn(b: array of byte): (int, ref Emsg);
		text:	fn(m: self ref Emsg): string;
	};
	
	ETmsg: adt {
		pick {
		Readerror =>
			error:	string;
		ExactusMsg =>
			msg:	ref Emsg;
		ModbusMsg =>
			addr:	byte;
			msg:	ref Modbus->TMmsg;
			crc:	int;
		}
		
		packedsize:	fn(nil: self ref ETmsg): int;
		pack:	fn(nil: self ref ETmsg): array of byte;
		
		dtype:	fn(nil: self ref ETmsg): (ref Emsg, ref Modbus->TMmsg);
	};
	
	ERmsg: adt {
		pick {
		Readerror =>
			error:	string;
		ExactusMsg =>
			msg:	ref Emsg;
		ModbusMsg =>
			msg:	ref Modbus->RMmsg;
		}
		
		packedsize:	fn(nil: self ref ERmsg): int;
		pack:	fn(nil: self ref ERmsg): array of byte;
		
		dtype:	fn(nil: self ref ERmsg): (ref Emsg, ref Modbus->RMmsg);
		tostring:	fn(nil: self ref ERmsg): string;
	};
	
	# TemperaSure binary data record
	Trecord: adt {
		time: int;
		temp0:	real;
		temp1:	real;
		temp2:	real;
		current1:	real;
		current2:	real;
		etemp1:	real;
		etemp2:	real;
		emissivity:	real;
		
		pack:	fn(nil: self ref Trecord): array of byte;
		unpack: fn(b: array of byte): (int, ref Trecord);
	};
	
	init:	fn();
	debug:	fn(f: int);
	
	open:	fn(path: string): ref Exactus->EPort;
	close:		fn(p: ref EPort): ref Sys->Connection;
	readreply:	fn(p: ref EPort, ms: int): (ref ERmsg, array of byte, string);
	write: fn(p: ref EPort, b: array of byte): int;
	
	exactusmode:	fn(p: ref EPort);
	modbusmode: 	fn(p: ref EPort);
	
	swapendian:	fn(b: array of byte): array of byte;

	escape:		fn(buf: array of byte): array of byte;
	deescape:	fn(esc: byte, buf: array of byte, n: int): (int, array of byte);
	
	lrc:	fn(buf: array of byte): byte;
	ieee754:	fn(b: array of byte): real;
	
	graphrate:	fn(p: ref EPort): int;
	set_graphrate:	fn(p: ref EPort, r: int);
	
	# Modbus mode queries
	serialnumber:	fn(p: ref EPort): string;
	temperature:	fn(p: ref EPort): real;
};
