/*
	CLIController.m
*/

#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <sys/types.h>
#import <sys/ptrace.h>
#import <sys/syscall.h>

#import "CLIController.h"
#import "ExeProcessor.h"
#import "PPCProcessor.h"
#import "X86Processor.h"
#import "UserDefaultKeys.h"

#import "SmartCrashReportsInstall.h"

// ============================================================================

@implementation CLIController

//	initialize
// ----------------------------------------------------------------------------

+ (void)initialize
{
	NSUserDefaultsController*	theController	=
		[NSUserDefaultsController sharedUserDefaultsController];
	NSDictionary*				theValues		=
		[NSDictionary dictionaryWithObjectsAndKeys:
		@"1",		AskOutputDirKey,
		@"YES",		DemangleCppNamesKey,
		@"YES",		EntabOutputKey,
		@"YES",		OpenOutputFileKey,
		@"BBEdit",	OutputAppKey,
		@"txt",		OutputFileExtensionKey,
		@"output",	OutputFileNameKey,
		@"NO",		SeparateLogicalBlocksKey,
		@"YES",		ShowDataSectionKey,
		@"YES",		ShowIvarTypesKey,
		@"YES",		ShowLocalOffsetsKey,
		@"YES",		ShowMD5Key,
		@"YES",		ShowMethodReturnTypesKey,
		@"0",		UseCustomNameKey,
		@"YES",		VerboseMsgSendsKey,
		nil];

	[theController setInitialValues: theValues];
	[[theController defaults] registerDefaults: theValues];
}

//	init
// ----------------------------------------------------------------------------

- (id)init
{
	self = [super init];
	return self;
}

//	initWithArgs:count:
// ----------------------------------------------------------------------------

- (id)initWithArgs: (char**) argv
			 count: (SInt32) argc
{
	self = [super init];

	if (!self)
		return nil;

	BOOL	localOffsets			= true;		// l
	BOOL	entabOutput				= true;		// e
	BOOL	dataSections			= true;		// d
	BOOL	checksum				= true;		// c
	BOOL	verboseMsgSends			= true;		// m
	BOOL	separateLogicalBlocks	= false;	// b
	BOOL	demangleCPNames			= true;		// n
	BOOL	returnTypes				= true;		// r
	BOOL	variableTypes			= true;		// v

	UInt32	i, j;

	for (i = 1; i < argc; i++)
	{
		if (argv[i][0] == '-')
		{
			for (j = 1; argv[i][j] != '\0'; j++)
			{
				switch (argv[i][j])
				{
					case 'l':
						localOffsets	= !localOffsets;
						break;
					case 'e':
						entabOutput	= !entabOutput;
						break;
					case 'd':
						dataSections	= !dataSections;
						break;
					case 'c':
						checksum	= !checksum;
						break;
					case 'm':
						verboseMsgSends	= !verboseMsgSends;
						break;
					case 'b':
						separateLogicalBlocks	= !separateLogicalBlocks;
						break;
					case 'n':
						demangleCPNames	= !demangleCPNames;
						break;
					case 'r':
						returnTypes	= !returnTypes;
						break;
					case 'v':
						variableTypes	= !variableTypes;
						break;
					case 'V':
						mVerify	= !mVerify;
						break;

					default:
						fprintf(stderr, "otx: unknown argument: '%c'\n",
							argv[i][j]);
						break;
				}
			}

			NSString*	origFilePath	= [NSString stringWithCString:
				&argv[i + 1][0] encoding: NSMacOSRomanStringEncoding];

			mOFile	= [NSURL fileURLWithPath: origFilePath];
		}
		else	// no flags, grab the file path
		{
			NSString*	origFilePath	= [NSString stringWithCString: &argv[i][0]
				encoding: NSMacOSRomanStringEncoding];

			mOFile	= [NSURL fileURLWithPath: origFilePath];
		}
	}

	if (mOFile)
		[mOFile retain];
	else
	{
		fprintf(stderr, "otx: invalid file\n");
		[self release];
		return nil;
	}

/**/
mArchSelector	= CPU_TYPE_POWERPC;
/**/

	NSUserDefaults*	defaults	= [NSUserDefaults standardUserDefaults];

	[defaults setBool: localOffsets forKey: ShowLocalOffsetsKey];
	[defaults setBool: entabOutput forKey: EntabOutputKey];
	[defaults setBool: dataSections forKey: ShowDataSectionKey];
	[defaults setBool: checksum forKey: ShowMD5Key];
	[defaults setBool: verboseMsgSends forKey: VerboseMsgSendsKey];
	[defaults setBool: separateLogicalBlocks forKey: SeparateLogicalBlocksKey];
	[defaults setBool: demangleCPNames forKey: DemangleCppNamesKey];
	[defaults setBool: returnTypes forKey: ShowMethodReturnTypesKey];
	[defaults setBool: variableTypes forKey: ShowIvarTypesKey];

	return self;
}

//	dealloc
// ----------------------------------------------------------------------------

- (void)dealloc
{
	if (mOFile)
		[mOFile release];

	if (mExeName)
		[mExeName release];

//	if (mOutputFileLabel)
//		[mOutputFileLabel release];

//	if (mOutputFileName)
//		[mOutputFileName release];

//	if (mOutputFilePath)
//		[mOutputFilePath release];

//	if (mPrefsViews)
//		free(mPrefsViews);

	[super dealloc];
}

#pragma mark -
//	newPackageFile:
// ----------------------------------------------------------------------------
//	Attempt to drill into the package to the executable. Fails when exe name
//	is different from app name, and when the exe is unreadable.

- (void)newPackageFile: (NSURL*)inPackageFile
{
//	if (mOutputFilePath)
//		[mOutputFilePath release];

	NSString*	origPath	= [inPackageFile path];
//	[mOutputFilePath retain];

	NSString*		theExeName	=
		[[origPath stringByDeletingPathExtension] lastPathComponent];
	NSString*		theExePath	=
	[[[origPath stringByAppendingPathComponent: @"Contents"]
		stringByAppendingPathComponent: @"MacOS"]
		stringByAppendingPathComponent: theExeName];
	NSFileManager*	theFileMan	= [NSFileManager defaultManager];

	if ([theFileMan isExecutableFileAtPath: theExePath])
		[self newOFile: [NSURL fileURLWithPath: theExePath] needsPath: false];
	else
		[self doDrillErrorAlert: theExePath];
}

//	newOFile:
// ----------------------------------------------------------------------------

- (void)newOFile: (NSURL*)inOFile
	   needsPath: (BOOL)inNeedsPath
{
	if (mOFile)
		[mOFile release];

	if (mExeName)
		[mExeName release];

	mOFile	= inOFile;
	[mOFile retain];

/*	if (inNeedsPath)
	{
		if (mOutputFilePath)
			[mOutputFilePath release];

		mOutputFilePath	= [mOFile path];
		[mOutputFilePath retain];
	}

	mExeName	= [[mOutputFilePath
		stringByDeletingPathExtension] lastPathComponent];*/
	mExeName	= [[[inOFile path]
		stringByDeletingPathExtension] lastPathComponent];
	[mExeName retain];
}

#pragma mark -
//	processFile:
// ----------------------------------------------------------------------------

- (IBAction)processFile: (id)sender
{
	if (!mOFile)
		return;

	mExeIsFat	= mArchMagic == FAT_MAGIC || mArchMagic == FAT_CIGAM;

	if ([self checkOtool] != noErr)
	{
		printf("otx: otool not found\n");
//		[self doOtoolAlertSheet];
		return;
	}

	Class	procClass	= nil;

	switch (mArchSelector)
	{
		case CPU_TYPE_POWERPC:
			procClass	= [PPCProcessor class];
			break;

		case CPU_TYPE_I386:
			procClass	= [X86Processor class];
			break;

		default:
			printf("otx: [CLIController processFile]: "
				"unknown arch type: %d", mArchSelector);
			break;
	}

	if (!procClass)
		return;

	id	theProcessor	=
		[[procClass alloc] initWithURL: mOFile andController: self];

	if (!theProcessor)
	{
		printf("otx: -[CLIController processFile]: "
			"unable to create processor.\n");
		return;
	}

	if (![theProcessor processExe: nil])
	{
		printf("otx: -[CLIController processFile]: "
			"possible permission error\n");
//		[self doErrorAlertSheet];
		[theProcessor release];
		return;
	}

	[theProcessor release];

//	NSUserDefaults*	theDefaults	= [NSUserDefaults standardUserDefaults];

//	if ([theDefaults boolForKey: OpenOutputFileKey])
//		[[NSWorkspace sharedWorkspace] openFile: mOutputFilePath
//			withApplication: [theDefaults objectForKey: OutputAppKey]];
}

//	verifyNops:
// ----------------------------------------------------------------------------
//	Create an instance of xxxProcessor to search for obfuscated nops. If any
//	are found, let user decide to fix them or not.

- (IBAction)verifyNops: (id)sender
{
	switch (mArchSelector)
	{
		case CPU_TYPE_I386:
		{
			X86Processor*	theProcessor	=
				[[X86Processor alloc] initWithURL: mOFile andController: self];

			if (!theProcessor)
			{
				printf("otx: -[CLIController verifyNops]: "
					"unable to create processor.\n");
				return;
			}

			unsigned char**	foundList	= nil;
			UInt32			foundCount	= 0;

			if ([theProcessor verifyNops: &foundList
				numFound: &foundCount])
			{
/*				NopList*	theInfo	= malloc(sizeof(NopList));

				theInfo->list	= foundList;
				theInfo->count	= foundCount;

				[theAlert addButtonWithTitle: @"Fix"];
				[theAlert addButtonWithTitle: @"Cancel"];
				[theAlert setMessageText: @"Broken nop's found."];
				[theAlert setInformativeText: [NSString stringWithFormat:
					@"otx found %d broken nop's. Would you like to save "
					@"a copy of the executable with fixed nop's?",
					foundCount]];
				[theAlert beginSheetModalForWindow: mMainWindow
					modalDelegate: self didEndSelector:
					@selector(nopAlertDidEnd:returnCode:contextInfo:)
					contextInfo: theInfo];*/
			}
			else
			{
/*				[theAlert addButtonWithTitle: @"OK"];
				[theAlert setMessageText: @"The executable is healthy."];
				[theAlert beginSheetModalForWindow: mMainWindow
					modalDelegate: nil didEndSelector: nil contextInfo: nil];*/
			}

			[theProcessor release];

			break;
		}

		default:
			break;
	}
}

//	nopAlertDidEnd:returnCode:contextInfo:
// ----------------------------------------------------------------------------
//	Respond to user's decision to fix obfuscated nops.

- (void)nopAlertDidEnd: (NSAlert*)alert
			returnCode: (int)returnCode
		   contextInfo: (void*)contextInfo
{
	if (returnCode == NSAlertSecondButtonReturn)
		return;

	if (!contextInfo)
	{
		printf("otx: tried to fix nops with nil contextInfo\n");
		return;
	}

	NopList*	theNops	= (NopList*)contextInfo;

	if (!theNops->list)
	{
		printf("otx: tried to fix nops with nil NopList.list\n");
		free(theNops);
		return;
	}

	switch (mArchSelector)
	{
		case CPU_TYPE_I386:
		{
			X86Processor*	theProcessor	=
				[[X86Processor alloc] initWithURL: mOFile andController: self];

			if (!theProcessor)
			{
				printf("otx: -[CLIController nopAlertDidEnd]: "
					"unable to create processor.\n");
				return;
			}

			NSURL*	fixedFile	= nil;
//				[theProcessor fixNops: theNops toPath: mOutputFilePath];

			if (fixedFile)
			{
				mIgnoreArch	= true;
				[self newOFile: fixedFile needsPath: true];
			}
			else
				printf("otx: unable to fix nops\n");

			break;
		}

		default:
			break;
	}

	free(theNops->list);
	free(theNops);
}

#pragma mark -
//	checkOtool
// ----------------------------------------------------------------------------

- (SInt32)checkOtool
{
	char*		headerArg	= mExeIsFat ? "-f" : "-h";
	NSString*	otoolString	= [NSString stringWithFormat:
		@"otool %s '%@' > /dev/null", headerArg, [mOFile path]];

	return system(CSTRING(otoolString));
}

//	doOtoolAlert
// ----------------------------------------------------------------------------

- (void)doOtoolAlert
{
}

//	doLipoAlert
// ----------------------------------------------------------------------------

- (void)doLipoAlert
{
}

//	doErrorAlert
// ----------------------------------------------------------------------------

- (void)doErrorAlert
{
}

//	doDrillErrorAlert:
// ----------------------------------------------------------------------------

- (void)doDrillErrorAlert: (NSString*)inExePath
{
}

#pragma mark -
//	reportProgress:
// ----------------------------------------------------------------------------

- (void)reportProgress: (ProgressState*)inState
{
}

@end
