-------------------------------------
Translated Report (Full Report Below)
-------------------------------------
Process:             Embershard [49102]
Path:                /Applications/Embershard.app/Contents/MacOS/Embershard
Identifier:          com.embershard.app
Version:             0.1.0 (1)
Code Type:           ARM-64 (Native)
Role:                Foreground
Parent Process:      launchd [1]
Coalition:           com.embershard.app [5211]
User ID:             501

Date/Time:           2026-06-16 14:10:00.2950 +0200
Launch Time:         2026-06-16 14:02:19.4797 +0200
Hardware Model:      Mac16,13
OS Version:          macOS 26.0.1 (25A362)
Release Type:        User

Crash Reporter Key:  25235D4E-B7B1-BFAB-C160-E1D7B9C61DED
Incident Identifier: 13BECE1C-152D-4075-A260-094C9C45544B

Sleep/Wake UUID:       1D12B6B5-7C05-41CD-A565-1DE593145926

Time Awake Since Boot: 16000 seconds
Time Since Wake:       1333 seconds

System Integrity Protection: enabled

Triggered by Thread: 0

Exception Type:    EXC_CRASH (SIGABRT)
Exception Codes:   0x0000000000000000, 0x0000000000000000

Termination Reason:  Namespace SIGNAL, Code 6, Abort trap: 6
Terminating Process: Embershard [49102]


Application Specific Information:
abort() called


Thread 0 Crashed:
0   libsystem_kernel.dylib        	       0x1914de5b0 __pthread_kill + 8
1   libsystem_pthread.dylib       	       0x191518888 pthread_kill + 296
2   libsystem_c.dylib             	       0x19141e808 abort + 124
3   libggml-base.0.15.1.dylib     	       0x102cd9570 ggml_abort + 160
4   libggml-metal.0.15.1.dylib    	       0x102c12334 ggml_metal_rsets_free + 152
5   libggml-metal.0.15.1.dylib    	       0x102c12f5c ggml_metal_device_free + 24
6   libggml-metal.0.15.1.dylib    	       0x102c14984 std::__1::vector<std::__1::unique_ptr<ggml_metal_device, ggml_metal_device_deleter>, std::__1::allocator<std::__1::unique_ptr<ggml_metal_device, ggml_metal_device_deleter>>>::~vector[abi:ne200100]() + 72
7   libsystem_c.dylib             	       0x1913cd42c __cxa_finalize_ranges + 480
8   libsystem_c.dylib             	       0x1913cd1ec exit + 44
9   AppKit                        	       0x195ef48b0 -[NSApplication terminate:] + 2004
10  AppKit                        	       0x195ef3fac -[NSApplication _terminateFromSender:askIfShouldTerminate:saveWindows:] + 120
11  AppKit                        	       0x195b05de8 __52-[NSApplication(NSAppleEventHandling) _handleAEQuit]_block_invoke + 52
12  CoreFoundation                	       0x1915b76e4 __CFRUNLOOP_IS_CALLING_OUT_TO_A_BLOCK__ + 28
13  CoreFoundation                	       0x1915b7624 __CFRunLoopDoBlocks + 396
14  CoreFoundation                	       0x1915b6458 __CFRunLoopRun + 804
15  CoreFoundation                	       0x191674898 _CFRunLoopRunSpecificWithOptions + 532
16  HIToolbox                     	       0x19dfb3730 RunCurrentEventLoopInMode + 316
17  HIToolbox                     	       0x19dfb69d0 ReceiveNextEventCommon + 488
18  HIToolbox                     	       0x19e1401f4 _BlockUntilNextEventMatchingListInMode + 48
19  AppKit                        	       0x195e8e25c _DPSBlockUntilNextEventMatchingListInMode + 236
20  AppKit                        	       0x1959a4edc _DPSNextEvent + 588
21  AppKit                        	       0x1963f7958 -[NSApplication(NSEventRouting) _nextEventMatchingEventMask:untilDate:inMode:dequeue:] + 688
22  AppKit                        	       0x1963f7664 -[NSApplication(NSEventRouting) nextEventMatchingMask:untilDate:inMode:dequeue:] + 72
23  AppKit                        	       0x19599d720 -[NSApplication run] + 368
24  AppKit                        	       0x195989694 NSApplicationMain + 880
25  SwiftUI                       	       0x1c4d05bc8 specialized runApp(_:) + 168
26  SwiftUI                       	       0x1c50bc674 runApp<A>(_:) + 112
27  SwiftUI                       	       0x1c537b918 static App.main() + 224
28  Embershard                    	       0x1027f4d44 static EmberShardApp.$main() + 52 [inlined]
29  Embershard                    	       0x1027f4d44 EmberShardApp_main + 64
30  dyld                          	       0x191159d54 start + 7184

Thread 1:: com.apple.NSEventThread
0   libsystem_kernel.dylib        	       0x1914d5c34 mach_msg2_trap + 8
1   libsystem_kernel.dylib        	       0x1914e8028 mach_msg2_internal + 76
2   libsystem_kernel.dylib        	       0x1914de98c mach_msg_overwrite + 484
3   libsystem_kernel.dylib        	       0x1914d5fb4 mach_msg + 24
4   CoreFoundation                	       0x1915b7c80 __CFRunLoopServiceMachPort + 160
5   CoreFoundation                	       0x1915b65d8 __CFRunLoopRun + 1188
6   CoreFoundation                	       0x191674898 _CFRunLoopRunSpecificWithOptions + 532
7   AppKit                        	       0x195a34a68 _NSEventThread + 184
8   libsystem_pthread.dylib       	       0x191518c08 _pthread_start + 136
9   libsystem_pthread.dylib       	       0x191513ba8 thread_start + 8

Thread 2:
0   libsystem_kernel.dylib        	       0x1914d92f4 __semwait_signal + 8
1   libsystem_c.dylib             	       0x1913b2d6c nanosleep + 220
2   libsystem_c.dylib             	       0x1913b2c84 usleep + 68
3   libggml-metal.0.15.1.dylib    	       0x102c12234 __ggml_metal_rsets_init_block_invoke + 100
4   libdispatch.dylib             	       0x19135cb5c _dispatch_call_block_and_release + 32
5   libdispatch.dylib             	       0x191376ac4 _dispatch_client_callout + 16
6   libdispatch.dylib             	       0x191392de8 _dispatch_queue_override_invoke.cold.3 + 108
7   libdispatch.dylib             	       0x19136137c _dispatch_queue_override_invoke + 848
8   libdispatch.dylib             	       0x19136efc8 _dispatch_root_queue_drain + 364
9   libdispatch.dylib             	       0x19136f784 _dispatch_worker_thread2 + 180
10  libsystem_pthread.dylib       	       0x191514e10 _pthread_wqthread + 232
11  libsystem_pthread.dylib       	       0x191513b9c start_wqthread + 8

Thread 3:

Thread 4:

Thread 5:

Thread 6:

Thread 7:


Thread 0 crashed with ARM Thread State (64-bit):
    x0: 0x0000000000000000   x1: 0x0000000000000000   x2: 0x0000000000000000   x3: 0x0000000000000000
    x4: 0x00000001914219b8   x5: 0x000000016d640890   x6: 0x0000000000000034   x7: 0x0000000000000000
    x8: 0x143019bd13a28162   x9: 0x143019bcee4ec962  x10: 0x00000000000003bc  x11: 0x0000000000000004
   x12: 0x0000000000000004  x13: 0x000000016d6405c4  x14: 0x000000018015385c  x15: 0x0000000000000001
   x16: 0x0000000000000148  x17: 0x00000001ff4fa008  x18: 0x0000000000000000  x19: 0x0000000000000006
   x20: 0x0000000000000103  x21: 0x00000001fdec48e0  x22: 0x0000000ae3fef700  x23: 0x0000000000000000
   x24: 0x0000000000000002  x25: 0x00000001fdece000  x26: 0x0000000000000004  x27: 0x0000000ae3fef710
   x28: 0x0000000000000003   fp: 0x000000016d641180   lr: 0x0000000191518888
    sp: 0x000000016d641160   pc: 0x00000001914de5b0 cpsr: 0x40000000
   far: 0x0000000000000000  esr: 0x56000080 (Syscall)

Binary Images:
       0x1027bc000 -        0x10287ffff com.embershard.app (0.1.0) <fc158b23-4473-3a9e-8414-b0f4be51246b> /Applications/Embershard.app/Contents/MacOS/Embershard
       0x102e68000 -        0x10300ffff libllama.0.0.1.dylib (*) <1ff8e4ae-f691-3f6a-a608-089bd0bc09f1> /Users/USER/*/libllama.0.0.1.dylib
       0x102ab0000 -        0x102ab7fff libggml.0.15.1.dylib (*) <efa2467c-86b7-30bb-9a32-b2517edb9fdb> /Users/USER/*/libggml.0.15.1.dylib
       0x102c0c000 -        0x102c2ffff libggml-metal.0.15.1.dylib (*) <c4bc4044-45e4-3c09-9092-222a5506fa00> /Users/USER/*/libggml-metal.0.15.1.dylib
       0x102ac4000 -        0x102ac7fff libggml-blas.0.15.1.dylib (*) <3450ad78-6f89-3f2e-9191-6188d3faf831> /Users/USER/*/libggml-blas.0.15.1.dylib
       0x1030c4000 -        0x10318bfff libggml-cpu.0.15.1.dylib (*) <ab3ca299-1c78-3fd3-b5d9-420959d19752> /Users/USER/*/libggml-cpu.0.15.1.dylib
       0x102cd8000 -        0x102d6ffff libggml-base.0.15.1.dylib (*) <2367b618-9c50-3769-90b2-1a65166a0428> /Users/USER/*/libggml-base.0.15.1.dylib
       0x10af30000 -        0x10af3bfff libobjc-trampolines.dylib (*) <580e4b29-8304-342d-a21c-2a869364dc35> /usr/lib/libobjc-trampolines.dylib
       0x1178f8000 -        0x11811bfff com.apple.AGXMetalG16G-B0 (340.26.3) <2170a88b-3de9-3ecc-927d-9690438526d0> /System/Library/Extensions/AGXMetalG16G_B0.bundle/Contents/MacOS/AGXMetalG16G_B0
       0x1914d5000 -        0x19151145f libsystem_kernel.dylib (*) <2eb73bf1-8c71-3e1f-a160-6da83dc82606> /usr/lib/system/libsystem_kernel.dylib
       0x191512000 -        0x19151eabb libsystem_pthread.dylib (*) <5d31d65c-2ecf-36da-84f5-ba4caab06adb> /usr/lib/system/libsystem_pthread.dylib
       0x1913a5000 -        0x191426ff7 libsystem_c.dylib (*) <1e2fc910-e211-3a48-90c1-402c82129ea8> /usr/lib/system/libsystem_c.dylib
       0x195985000 -        0x197080cdf com.apple.AppKit (6.9) <9aef8974-703a-3941-9b3d-de8c5ccb61d0> /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit
       0x191558000 -        0x191aa4f7f com.apple.CoreFoundation (6.9) <edb39786-80b1-3bff-b6c3-e33f2e3ca867> /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
       0x19def2000 -        0x19e1f46ff com.apple.HIToolbox (2.1.1) <f369023f-1a24-3f3f-9056-6f5248071e8c> /System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox
       0x1c4bf5000 -        0x1c633e9df com.apple.SwiftUI (7.0.84.1.411) <0da860be-114f-3227-b02f-ca1cb8ae9050> /System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI
       0x191151000 -        0x1911eff73 dyld (*) <abfd3247-50ac-3c8e-b72a-83710166e982> /usr/lib/dyld
               0x0 - 0xffffffffffffffff ??? (*) <00000000-0000-0000-0000-000000000000> ???
       0x19135b000 -        0x1913a1e9f libdispatch.dylib (*) <17d849c6-a785-3dbb-bfb5-8321706c4b8d> /usr/lib/system/libdispatch.dylib

External Modification Summary:
  Calls made by other processes targeting this process:
    task_for_pid: 0
    thread_create: 0
    thread_set_state: 0
  Calls made by this process:
    task_for_pid: 0
    thread_create: 0
    thread_set_state: 0
  Calls made by all processes on this machine:
    task_for_pid: 0
    thread_create: 0
    thread_set_state: 0

VM Region Summary:
ReadOnly portion of Libraries: Total=1.8G resident=0K(0%) swapped_out_or_unallocated=1.8G(100%)
Writable regions: Total=2.6G written=1810K(0%) resident=1698K(0%) swapped_out=112K(0%) unallocated=2.6G(100%)

                                VIRTUAL   REGION 
REGION TYPE                        SIZE    COUNT (non-coalesced) 
===========                     =======  ======= 
Accelerate framework               128K        1 
Activity Tracing                   256K        1 
AttributeGraph Data               1024K        1 
CG image                           688K       10 
ColorSync                          640K       30 
CoreAnimation                     2672K      102 
CoreGraphics                        32K        2 
CoreUI image data                 1152K       10 
Foundation                          48K        2 
Kernel Alloc Once                   32K        1 
MALLOC                           243.1M       76 
MALLOC guard page                 3136K        4 
STACK GUARD                       56.1M        8 
Stack                             11.7M        8 
VM_ALLOCATE                        2.4G       33 
__AUTH                            5817K      654 
__AUTH_CONST                      89.0M     1039 
__CTF                               824        1 
__DATA                            30.8M      996 
__DATA_CONST                      33.0M     1053 
__DATA_DIRTY                      8881K      899 
__FONT_DATA                        2352        1 
__INFO_FILTER                         8        1 
__LINKEDIT                       598.6M       10 
__OBJC_RO                         78.1M        1 
__OBJC_RW                         2561K        1 
__TEXT                             1.2G     1068 
__TEXT (graphics)                 12.1M        8 
__TPRO_CONST                       128K        2 
mapped file                      391.1M       66 
page table in kernel              1698K        1 
shared memory                     9056K       16 
===========                     =======  ======= 
TOTAL                              5.1G     6106 


-----------
Full Report
-----------

{"app_name":"Embershard","timestamp":"2026-06-16 14:10:21.00 +0200","app_version":"0.1.0","slice_uuid":"fc158b23-4473-3a9e-8414-b0f4be51246b","build_version":"1","platform":1,"bundleID":"com.embershard.app","share_with_app_devs":0,"is_first_party":0,"bug_type":"309","os_version":"macOS 26.0.1 (25A362)","roots_installed":0,"name":"Embershard","incident_id":"13BECE1C-152D-4075-A260-094C9C45544B"}
{
  "uptime" : 16000,
  "procRole" : "Foreground",
  "version" : 2,
  "userID" : 501,
  "deployVersion" : 210,
  "modelCode" : "Mac16,13",
  "coalitionID" : 5211,
  "osVersion" : {
    "train" : "macOS 26.0.1",
    "build" : "25A362",
    "releaseType" : "User"
  },
  "captureTime" : "2026-06-16 14:10:00.2950 +0200",
  "codeSigningMonitor" : 2,
  "incident" : "13BECE1C-152D-4075-A260-094C9C45544B",
  "pid" : 49102,
  "translated" : false,
  "cpuType" : "ARM-64",
  "roots_installed" : 0,
  "bug_type" : "309",
  "procLaunch" : "2026-06-16 14:02:19.4797 +0200",
  "procStartAbsTime" : 390517392864,
  "procExitAbsTime" : 401576834900,
  "procName" : "Embershard",
  "procPath" : "\/Applications\/Embershard.app\/Contents\/MacOS\/Embershard",
  "bundleInfo" : {"CFBundleShortVersionString":"0.1.0","CFBundleVersion":"1","CFBundleIdentifier":"com.embershard.app"},
  "storeInfo" : {"deviceIdentifierForVendor":"F0DB9902-5526-5C13-A4AE-D1B2E38E5D40","thirdParty":true},
  "parentProc" : "launchd",
  "parentPid" : 1,
  "coalitionName" : "com.embershard.app",
  "crashReporterKey" : "25235D4E-B7B1-BFAB-C160-E1D7B9C61DED",
  "developerMode" : 1,
  "codeSigningID" : "com.embershard.app",
  "codeSigningTeamID" : "",
  "codeSigningFlags" : 570425857,
  "codeSigningValidationCategory" : 10,
  "codeSigningTrustLevel" : 4294967295,
  "codeSigningAuxiliaryInfo" : 0,
  "instructionByteStream" : {"beforePC":"fyMD1f17v6n9AwCRFOD\/l78DAJH9e8Go\/w9f1sADX9YQKYDSARAA1A==","atPC":"AwEAVH8jA9X9e7+p\/QMAkQng\/5e\/AwCR\/XvBqP8PX9bAA1\/WcAqA0g=="},
  "bootSessionUUID" : "25F0457B-E7D2-4D71-B18F-D40A1D8ABB0B",
  "wakeTime" : 1333,
  "sleepWakeUUID" : "1D12B6B5-7C05-41CD-A565-1DE593145926",
  "sip" : "enabled",
  "exception" : {"codes":"0x0000000000000000, 0x0000000000000000","rawCodes":[0,0],"type":"EXC_CRASH","signal":"SIGABRT"},
  "termination" : {"flags":0,"code":6,"namespace":"SIGNAL","indicator":"Abort trap: 6","byProc":"Embershard","byPid":49102},
  "asi" : {"libsystem_c.dylib":["abort() called"]},
  "extMods" : {"caller":{"thread_create":0,"thread_set_state":0,"task_for_pid":0},"system":{"thread_create":0,"thread_set_state":0,"task_for_pid":0},"targeted":{"thread_create":0,"thread_set_state":0,"task_for_pid":0},"warnings":0},
  "faultingThread" : 0,
  "threads" : [{"triggered":true,"id":521277,"threadState":{"x":[{"value":0},{"value":0},{"value":0},{"value":0},{"value":6731995576,"symbolLocation":0,"symbol":"__vfprintf.xdigs_lower"},{"value":6130239632},{"value":52},{"value":0},{"value":1454690979509600610},{"value":1454690978883357026},{"value":956},{"value":4},{"value":4},{"value":6130238916},{"value":6443841628},{"value":1},{"value":328},{"value":8578375688},{"value":0},{"value":6},{"value":259},{"value":8555088096,"symbolLocation":224,"symbol":"_main_thread"},{"value":46774810368},{"value":0},{"value":2},{"value":8555126784,"symbolLocation":0,"symbol":"__scounted"},{"value":4},{"value":46774810384},{"value":3}],"flavor":"ARM_THREAD_STATE64","lr":{"value":6733006984},"cpsr":{"value":1073741824},"fp":{"value":6130241920},"sp":{"value":6130241888},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6732768688,"matchesCrashFrame":1},"far":{"value":0}},"frames":[{"imageOffset":38320,"symbol":"__pthread_kill","symbolLocation":8,"imageIndex":9},{"imageOffset":26760,"symbol":"pthread_kill","symbolLocation":296,"imageIndex":10},{"imageOffset":497672,"symbol":"abort","symbolLocation":124,"imageIndex":11},{"imageOffset":5488,"symbol":"ggml_abort","symbolLocation":160,"imageIndex":6},{"imageOffset":25396,"symbol":"ggml_metal_rsets_free","symbolLocation":152,"imageIndex":3},{"imageOffset":28508,"symbol":"ggml_metal_device_free","symbolLocation":24,"imageIndex":3},{"imageOffset":35204,"symbol":"std::__1::vector<std::__1::unique_ptr<ggml_metal_device, ggml_metal_device_deleter>, std::__1::allocator<std::__1::unique_ptr<ggml_metal_device, ggml_metal_device_deleter>>>::~vector[abi:ne200100]()","symbolLocation":72,"imageIndex":3},{"imageOffset":164908,"symbol":"__cxa_finalize_ranges","symbolLocation":480,"imageIndex":11},{"imageOffset":164332,"symbol":"exit","symbolLocation":44,"imageIndex":11},{"imageOffset":5699760,"symbol":"-[NSApplication terminate:]","symbolLocation":2004,"imageIndex":12},{"imageOffset":5697452,"symbol":"-[NSApplication _terminateFromSender:askIfShouldTerminate:saveWindows:]","symbolLocation":120,"imageIndex":12},{"imageOffset":1576424,"symbol":"__52-[NSApplication(NSAppleEventHandling) _handleAEQuit]_block_invoke","symbolLocation":52,"imageIndex":12},{"imageOffset":390884,"symbol":"__CFRUNLOOP_IS_CALLING_OUT_TO_A_BLOCK__","symbolLocation":28,"imageIndex":13},{"imageOffset":390692,"symbol":"__CFRunLoopDoBlocks","symbolLocation":396,"imageIndex":13},{"imageOffset":386136,"symbol":"__CFRunLoopRun","symbolLocation":804,"imageIndex":13},{"imageOffset":1165464,"symbol":"_CFRunLoopRunSpecificWithOptions","symbolLocation":532,"imageIndex":13},{"imageOffset":792368,"symbol":"RunCurrentEventLoopInMode","symbolLocation":316,"imageIndex":14},{"imageOffset":805328,"symbol":"ReceiveNextEventCommon","symbolLocation":488,"imageIndex":14},{"imageOffset":2417140,"symbol":"_BlockUntilNextEventMatchingListInMode","symbolLocation":48,"imageIndex":14},{"imageOffset":5280348,"symbol":"_DPSBlockUntilNextEventMatchingListInMode","symbolLocation":236,"imageIndex":12},{"imageOffset":130780,"symbol":"_DPSNextEvent","symbolLocation":588,"imageIndex":12},{"imageOffset":10955096,"symbol":"-[NSApplication(NSEventRouting) _nextEventMatchingEventMask:untilDate:inMode:dequeue:]","symbolLocation":688,"imageIndex":12},{"imageOffset":10954340,"symbol":"-[NSApplication(NSEventRouting) nextEventMatchingMask:untilDate:inMode:dequeue:]","symbolLocation":72,"imageIndex":12},{"imageOffset":100128,"symbol":"-[NSApplication run]","symbolLocation":368,"imageIndex":12},{"imageOffset":18068,"symbol":"NSApplicationMain","symbolLocation":880,"imageIndex":12},{"imageOffset":1117128,"symbol":"specialized runApp(_:)","symbolLocation":168,"imageIndex":15},{"imageOffset":5011060,"symbol":"runApp<A>(_:)","symbolLocation":112,"imageIndex":15},{"imageOffset":7891224,"symbol":"static App.main()","symbolLocation":224,"imageIndex":15},{"imageOffset":232772,"sourceFile":"EmberShardApp.swift","symbol":"static EmberShardApp.$main()","imageIndex":0,"symbolLocation":52,"inline":true},{"imageOffset":232772,"sourceFile":"EmberShardApp.swift","symbol":"EmberShardApp_main","symbolLocation":64,"imageIndex":0},{"imageOffset":36180,"symbol":"start","symbolLocation":7184,"imageIndex":16}]},{"id":521341,"name":"com.apple.NSEventThread","threadState":{"x":[{"value":268451845},{"value":21592279046},{"value":8589934592},{"value":133053791862784},{"value":0},{"value":133053791862784},{"value":2},{"value":4294967295},{"value":0},{"value":17179869184},{"value":0},{"value":2},{"value":0},{"value":0},{"value":30979},{"value":0},{"value":18446744073709551569},{"value":8578377488},{"value":0},{"value":4294967295},{"value":2},{"value":133053791862784},{"value":0},{"value":133053791862784},{"value":6133096584},{"value":8589934592},{"value":21592279046},{"value":18446744073709550527},{"value":4412409862}],"flavor":"ARM_THREAD_STATE64","lr":{"value":6732808232},"cpsr":{"value":0},"fp":{"value":6133096432},"sp":{"value":6133096352},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6732733492},"far":{"value":0}},"frames":[{"imageOffset":3124,"symbol":"mach_msg2_trap","symbolLocation":8,"imageIndex":9},{"imageOffset":77864,"symbol":"mach_msg2_internal","symbolLocation":76,"imageIndex":9},{"imageOffset":39308,"symbol":"mach_msg_overwrite","symbolLocation":484,"imageIndex":9},{"imageOffset":4020,"symbol":"mach_msg","symbolLocation":24,"imageIndex":9},{"imageOffset":392320,"symbol":"__CFRunLoopServiceMachPort","symbolLocation":160,"imageIndex":13},{"imageOffset":386520,"symbol":"__CFRunLoopRun","symbolLocation":1188,"imageIndex":13},{"imageOffset":1165464,"symbol":"_CFRunLoopRunSpecificWithOptions","symbolLocation":532,"imageIndex":13},{"imageOffset":719464,"symbol":"_NSEventThread","symbolLocation":184,"imageIndex":12},{"imageOffset":27656,"symbol":"_pthread_start","symbolLocation":136,"imageIndex":10},{"imageOffset":7080,"symbol":"thread_start","symbolLocation":8,"imageIndex":10}]},{"id":521377,"frames":[{"imageOffset":17140,"symbol":"__semwait_signal","symbolLocation":8,"imageIndex":9},{"imageOffset":56684,"symbol":"nanosleep","symbolLocation":220,"imageIndex":11},{"imageOffset":56452,"symbol":"usleep","symbolLocation":68,"imageIndex":11},{"imageOffset":25140,"symbol":"__ggml_metal_rsets_init_block_invoke","symbolLocation":100,"imageIndex":3},{"imageOffset":7004,"symbol":"_dispatch_call_block_and_release","symbolLocation":32,"imageIndex":18},{"imageOffset":113348,"symbol":"_dispatch_client_callout","symbolLocation":16,"imageIndex":18},{"imageOffset":228840,"symbol":"_dispatch_queue_override_invoke.cold.3","symbolLocation":108,"imageIndex":18},{"imageOffset":25468,"symbol":"_dispatch_queue_override_invoke","symbolLocation":848,"imageIndex":18},{"imageOffset":81864,"symbol":"_dispatch_root_queue_drain","symbolLocation":364,"imageIndex":18},{"imageOffset":83844,"symbol":"_dispatch_worker_thread2","symbolLocation":180,"imageIndex":18},{"imageOffset":11792,"symbol":"_pthread_wqthread","symbolLocation":232,"imageIndex":10},{"imageOffset":7068,"symbol":"start_wqthread","symbolLocation":8,"imageIndex":10}],"threadState":{"x":[{"value":4},{"value":0},{"value":1},{"value":1},{"value":0},{"value":5000000},{"value":0},{"value":0},{"value":8555129632,"symbolLocation":0,"symbol":"clock_sem"},{"value":3},{"value":17},{"value":2},{"value":2},{"value":46809077648},{"value":72057602593215145,"symbolLocation":72057594037927937,"symbol":"OBJC_CLASS_$_NSLock"},{"value":8555287208,"symbolLocation":0,"symbol":"OBJC_CLASS_$_NSLock"},{"value":334},{"value":8578375736},{"value":0},{"value":0},{"value":6135967216},{"value":4294967295},{"value":1000},{"value":6135967968},{"value":8555108416,"symbolLocation":1536,"symbol":"_dispatch_root_queues"},{"value":1535},{"value":8520500996,"symbolLocation":0,"symbol":"_dispatch_continuation_cache_limit"},{"value":284},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":6731541868},"cpsr":{"value":2684354560},"fp":{"value":6135967200},"sp":{"value":6135967152},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6732747508},"far":{"value":0}}},{"id":530812,"frames":[],"threadState":{"x":[{"value":6131380224},{"value":87371},{"value":6130843648},{"value":0},{"value":409604},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":0},"fp":{"value":0},"sp":{"value":6131380224},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6732987284},"far":{"value":0}}},{"id":531053,"frames":[],"threadState":{"x":[{"value":6132527104},{"value":60843},{"value":6131990528},{"value":0},{"value":409604},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":0},"fp":{"value":0},"sp":{"value":6132527104},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6732987284},"far":{"value":0}}},{"id":531055,"frames":[],"threadState":{"x":[{"value":6134820864},{"value":75147},{"value":6134284288},{"value":0},{"value":409604},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":0},"fp":{"value":0},"sp":{"value":6134820864},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6732987284},"far":{"value":0}}},{"id":532278,"frames":[],"threadState":{"x":[{"value":6130806784},{"value":114979},{"value":6130270208},{"value":0},{"value":409602},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":0},"fp":{"value":0},"sp":{"value":6130806784},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6732987284},"far":{"value":0}}},{"id":532279,"frames":[],"threadState":{"x":[{"value":6131953664},{"value":71523},{"value":6131417088},{"value":0},{"value":409604},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":0},"fp":{"value":0},"sp":{"value":6131953664},"esr":{"value":1442840704,"description":"(Syscall)"},"pc":{"value":6732987284},"far":{"value":0}}}],
  "usedImages" : [
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4336631808,
    "CFBundleShortVersionString" : "0.1.0",
    "CFBundleIdentifier" : "com.embershard.app",
    "size" : 802816,
    "uuid" : "fc158b23-4473-3a9e-8414-b0f4be51246b",
    "path" : "\/Applications\/Embershard.app\/Contents\/MacOS\/Embershard",
    "name" : "Embershard",
    "CFBundleVersion" : "1"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4343627776,
    "size" : 1736704,
    "uuid" : "1ff8e4ae-f691-3f6a-a608-089bd0bc09f1",
    "path" : "\/Users\/USER\/*\/libllama.0.0.1.dylib",
    "name" : "libllama.0.0.1.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4339728384,
    "size" : 32768,
    "uuid" : "efa2467c-86b7-30bb-9a32-b2517edb9fdb",
    "path" : "\/Users\/USER\/*\/libggml.0.15.1.dylib",
    "name" : "libggml.0.15.1.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4341153792,
    "size" : 147456,
    "uuid" : "c4bc4044-45e4-3c09-9092-222a5506fa00",
    "path" : "\/Users\/USER\/*\/libggml-metal.0.15.1.dylib",
    "name" : "libggml-metal.0.15.1.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4339810304,
    "size" : 16384,
    "uuid" : "3450ad78-6f89-3f2e-9191-6188d3faf831",
    "path" : "\/Users\/USER\/*\/libggml-blas.0.15.1.dylib",
    "name" : "libggml-blas.0.15.1.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4346101760,
    "size" : 819200,
    "uuid" : "ab3ca299-1c78-3fd3-b5d9-420959d19752",
    "path" : "\/Users\/USER\/*\/libggml-cpu.0.15.1.dylib",
    "name" : "libggml-cpu.0.15.1.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4341989376,
    "size" : 622592,
    "uuid" : "2367b618-9c50-3769-90b2-1a65166a0428",
    "path" : "\/Users\/USER\/*\/libggml-base.0.15.1.dylib",
    "name" : "libggml-base.0.15.1.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 4478664704,
    "size" : 49152,
    "uuid" : "580e4b29-8304-342d-a21c-2a869364dc35",
    "path" : "\/usr\/lib\/libobjc-trampolines.dylib",
    "name" : "libobjc-trampolines.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 4690247680,
    "CFBundleShortVersionString" : "340.26.3",
    "CFBundleIdentifier" : "com.apple.AGXMetalG16G-B0",
    "size" : 8536064,
    "uuid" : "2170a88b-3de9-3ecc-927d-9690438526d0",
    "path" : "\/System\/Library\/Extensions\/AGXMetalG16G_B0.bundle\/Contents\/MacOS\/AGXMetalG16G_B0",
    "name" : "AGXMetalG16G_B0",
    "CFBundleVersion" : "340.26.3"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6732730368,
    "size" : 246880,
    "uuid" : "2eb73bf1-8c71-3e1f-a160-6da83dc82606",
    "path" : "\/usr\/lib\/system\/libsystem_kernel.dylib",
    "name" : "libsystem_kernel.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6732980224,
    "size" : 51900,
    "uuid" : "5d31d65c-2ecf-36da-84f5-ba4caab06adb",
    "path" : "\/usr\/lib\/system\/libsystem_pthread.dylib",
    "name" : "libsystem_pthread.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6731485184,
    "size" : 532472,
    "uuid" : "1e2fc910-e211-3a48-90c1-402c82129ea8",
    "path" : "\/usr\/lib\/system\/libsystem_c.dylib",
    "name" : "libsystem_c.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6804754432,
    "CFBundleShortVersionString" : "6.9",
    "CFBundleIdentifier" : "com.apple.AppKit",
    "size" : 24100064,
    "uuid" : "9aef8974-703a-3941-9b3d-de8c5ccb61d0",
    "path" : "\/System\/Library\/Frameworks\/AppKit.framework\/Versions\/C\/AppKit",
    "name" : "AppKit",
    "CFBundleVersion" : "2685.10.110"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6733266944,
    "CFBundleShortVersionString" : "6.9",
    "CFBundleIdentifier" : "com.apple.CoreFoundation",
    "size" : 5558144,
    "uuid" : "edb39786-80b1-3bff-b6c3-e33f2e3ca867",
    "path" : "\/System\/Library\/Frameworks\/CoreFoundation.framework\/Versions\/A\/CoreFoundation",
    "name" : "CoreFoundation",
    "CFBundleVersion" : "4040.1.401"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6944661504,
    "CFBundleShortVersionString" : "2.1.1",
    "CFBundleIdentifier" : "com.apple.HIToolbox",
    "size" : 3155712,
    "uuid" : "f369023f-1a24-3f3f-9056-6f5248071e8c",
    "path" : "\/System\/Library\/Frameworks\/Carbon.framework\/Versions\/A\/Frameworks\/HIToolbox.framework\/Versions\/A\/HIToolbox",
    "name" : "HIToolbox"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 7595839488,
    "CFBundleShortVersionString" : "7.0.84.1.411",
    "CFBundleIdentifier" : "com.apple.SwiftUI",
    "size" : 24418784,
    "uuid" : "0da860be-114f-3227-b02f-ca1cb8ae9050",
    "path" : "\/System\/Library\/Frameworks\/SwiftUI.framework\/Versions\/A\/SwiftUI",
    "name" : "SwiftUI",
    "CFBundleVersion" : "7.0.84.1.411"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6729043968,
    "size" : 651124,
    "uuid" : "abfd3247-50ac-3c8e-b72a-83710166e982",
    "path" : "\/usr\/lib\/dyld",
    "name" : "dyld"
  },
  {
    "size" : 0,
    "source" : "A",
    "base" : 0,
    "uuid" : "00000000-0000-0000-0000-000000000000"
  },
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 6731182080,
    "size" : 290464,
    "uuid" : "17d849c6-a785-3dbb-bfb5-8321706c4b8d",
    "path" : "\/usr\/lib\/system\/libdispatch.dylib",
    "name" : "libdispatch.dylib"
  }
],
  "sharedCache" : {
  "base" : 6727974912,
  "size" : 5557583872,
  "uuid" : "4300eabe-4963-34ab-a648-3d68753cf4e1"
},
  "vmSummary" : "ReadOnly portion of Libraries: Total=1.8G resident=0K(0%) swapped_out_or_unallocated=1.8G(100%)\nWritable regions: Total=2.6G written=1810K(0%) resident=1698K(0%) swapped_out=112K(0%) unallocated=2.6G(100%)\n\n                                VIRTUAL   REGION \nREGION TYPE                        SIZE    COUNT (non-coalesced) \n===========                     =======  ======= \nAccelerate framework               128K        1 \nActivity Tracing                   256K        1 \nAttributeGraph Data               1024K        1 \nCG image                           688K       10 \nColorSync                          640K       30 \nCoreAnimation                     2672K      102 \nCoreGraphics                        32K        2 \nCoreUI image data                 1152K       10 \nFoundation                          48K        2 \nKernel Alloc Once                   32K        1 \nMALLOC                           243.1M       76 \nMALLOC guard page                 3136K        4 \nSTACK GUARD                       56.1M        8 \nStack                             11.7M        8 \nVM_ALLOCATE                        2.4G       33 \n__AUTH                            5817K      654 \n__AUTH_CONST                      89.0M     1039 \n__CTF                               824        1 \n__DATA                            30.8M      996 \n__DATA_CONST                      33.0M     1053 \n__DATA_DIRTY                      8881K      899 \n__FONT_DATA                        2352        1 \n__INFO_FILTER                         8        1 \n__LINKEDIT                       598.6M       10 \n__OBJC_RO                         78.1M        1 \n__OBJC_RW                         2561K        1 \n__TEXT                             1.2G     1068 \n__TEXT (graphics)                 12.1M        8 \n__TPRO_CONST                       128K        2 \nmapped file                      391.1M       66 \npage table in kernel              1698K        1 \nshared memory                     9056K       16 \n===========                     =======  ======= \nTOTAL                              5.1G     6106 \n",
  "legacyInfo" : {
  "threadTriggered" : {

  }
},
  "logWritingSignature" : "1fddda60d449b7d744f1a4d2f611f9d008c8b9a8",
  "trialInfo" : {
  "rollouts" : [
    {
      "rolloutId" : "682ef9612c2ae30e2f38d3a4",
      "factorPackIds" : [

      ],
      "deploymentId" : 240000006
    },
    {
      "rolloutId" : "64628732bf2f5257dedc8988",
      "factorPackIds" : [

      ],
      "deploymentId" : 240000001
    }
  ],
  "experiments" : [

  ]
}
}

Model: Mac16,13, BootROM 13822.1.2, proc 10:4:6 processors, 16 GB, SMC 
Graphics: Apple M4, Apple M4, Built-In
Display: Color LCD, spdisplays_2880x1864Retina, Main, MirrorOff, Online
Memory Module: LPDDR5, Micron
AirPort: spairport_wireless_card_type_wifi (0x14E4, 0x4388), wl0: Jul 23 2025 02:15:41 version 23.41.4.0.41.51.197 FWID 01-94e410f5
IO80211_driverkit-1525.88 "IO80211_driverkit-1525.88" Aug  6 2025 21:19:03
AirPort: 
Bluetooth: Version (null), 0 services, 0 devices, 0 incoming serial ports
Network Service: Wi-Fi, AirPort, en0
Network Service: VPN, VPN (com.fortinet.forticlient.macos.vpn), utun4
Thunderbolt Bus: MacBook Air, Apple Inc.
Thunderbolt Bus: MacBook Air, Apple Inc.