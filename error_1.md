-------------------------------------
Translated Report (Full Report Below)
-------------------------------------

Process:               Embershard [87144]
Path:                  /Applications/Embershard.app/Contents/MacOS/Embershard
Identifier:            com.embershard.app
Version:               0.1.5 (6)
Code Type:             ARM-64 (Native)
Parent Process:        launchd [1]
User ID:               501

Date/Time:             2026-06-17 18:01:12.1271 +0200
OS Version:            macOS 14.4 (23E214)
Report Version:        12
Anonymous UUID:        32832412-6FE1-4CD1-572D-550BF2C85412


Time Awake Since Boot: 8500 seconds

System Integrity Protection: enabled

Crashed Thread:        0  Dispatch queue: com.apple.main-thread

Exception Type:        EXC_BREAKPOINT (SIGTRAP)
Exception Codes:       0x0000000000000001, 0x0000000194dd8ee0

Termination Reason:    Namespace SIGNAL, Code 5 Trace/BPT trap: 5
Terminating Process:   exc handler [87144]

Thread 0 Crashed::  Dispatch queue: com.apple.main-thread
0   libswiftCore.dylib                   0x194dd8ee0 _assertionFailure(_:_:file:line:flags:) + 268
1   Embershard                           0x102adb1c0 closure #1 in variable initialization expression of static NSBundle.module + 612
2   Embershard                           0x102adaf4c one-time initialization function for module + 12
3   libdispatch.dylib                   0x184f363e8 _dispatch_client_callout + 20
4   libdispatch.dylib                   0x184f37c68 _dispatch_once_callout + 32
5   Embershard                           0x102a21b70 specialized WelcomeView.logoImage.getter + 424
6   Embershard                           0x102a1adfc closure #1 in closure #1 in WelcomeView.body.getter + 228
7   Embershard                           0x102a1a6b0 closure #1 in WelcomeView.body.getter + 96
8   Embershard                           0x102a1a4a8 WelcomeView.body.getter + 96
update() + 512
AG::data::ptr<AG::Node>, unsigned int) + 424
slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 720
update() + 512
AG::data::ptr<AG::Node>, unsigned int) + 424
slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 720
update() + 512
AG::data::ptr<AG::Node>, unsigned int) + 424
slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 720
update() + 512
AG::data::ptr<AG::Node>, unsigned int) + 424
slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 240
update() + 512
AG::data::ptr<AG::Node>, unsigned int) + 424
slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 720
update() + 512
AG::data::ptr<AG::Node>, unsigned int) + 424
slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 720
update() + 512
AG::data::ptr<AG::Node>, unsigned int) + 424
slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 720
update() + 512
AG::data::ptr<AG::Node>, unsigned int) + 424
slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 720
update() + 512
AG::data::ptr<AG::Node>, unsigned int) + 424
update() + 512
AG::data::ptr<AG::Node>, unsigned int) + 424
slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 720
update() + 512
AG::data::ptr<AG::Node>, unsigned int) + 424
slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 240
relativeTo:] + 372
relativeTo:] + 52
relativeTo:] + 44
CALLING_OUT_TO_AN_OBSERVER__ + 148
169 CoreFoundation                       0x18524edb8 ___CFXRegistrationPost_block_invoke + 88
userInfo:] + 88
sendFinishLaunchingNotification] + 172
NSAppleEventHandling) _handleAEOpenEvent:] + 504
NSAppleEventHandling) _handleCoreEvent:withReplyEvent:] + 492
withRawReply:handlerRefCon:] + 316
178 Foundation                           0x1862cd708 _NSAppleEventManagerGenericHandler + 80
NSEventRouting) _nextEventMatchingEventMask:untilDate:inMode:dequeue:] + 700
190 Embershard                           0x102a42e14 EmberShardApp_main + 64
191 dyld                                 0x184d5e0e0 start + 2360

Thread 1:
0   libsystem_pthread.dylib             0x1850e1d20 start_wqthread + 0

Thread 2::  Dispatch queue: com.apple.root.utility-qos
0   libswiftCore.dylib                   0x195199e94 swift_conformsToProtocolMaybeInstantiateSuperclasses(swift::TargetMetadata<swift::InProcess> const*, swift::TargetProtocolDescriptor<swift::InProcess> const*, bool)::$_8::operator()((anonymous namespace)::ConformanceSection const&) const::'lambda'(swift::TargetProtocolConformanceDescriptor<swift::InProcess> const&)::operator()(swift::TargetProtocolConformanceDescriptor<swift::InProcess> const&) const + 100
1   libswiftCore.dylib                   0x195198fac swift_conformsToProtocolMaybeInstantiateSuperclasses(swift::TargetMetadata<swift::InProcess> const*, swift::TargetProtocolDescriptor<swift::InProcess> const*, bool) + 3948
2   libswiftCore.dylib                   0x19519716c swift_conformsToProtocol + 156
3   AttributeGraph                       0x1b2697164 AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode) + 184
4   AttributeGraph                       0x1b26976b4 AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int) + 344
5   AttributeGraph                       0x1b2696394 AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool) + 56
6   AttributeGraph                       0x1b2696238 AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long) + 120
7   AttributeGraph                       0x1b267f608 AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long) + 180
8   AttributeGraph                       0x1b267eb4c AG::swift::metadata::visit(AG::swift::metadata_visitor&) const + 1244
9   AttributeGraph                       0x1b26972f0 AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode) + 580
10  AttributeGraph                       0x1b26976b4 AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int) + 344
11  AttributeGraph                       0x1b2696394 AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool) + 56
12  AttributeGraph                       0x1b2696238 AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long) + 120
13  AttributeGraph                       0x1b267f608 AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long) + 180
14  AttributeGraph                       0x1b267eb4c AG::swift::metadata::visit(AG::swift::metadata_visitor&) const + 1244
15  AttributeGraph                       0x1b26972f0 AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode) + 580
16  AttributeGraph                       0x1b26976b4 AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int) + 344
17  AttributeGraph                       0x1b2696394 AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool) + 56
18  AttributeGraph                       0x1b2696238 AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long) + 120
19  AttributeGraph                       0x1b267f608 AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long) + 180
20  AttributeGraph                       0x1b267eb4c AG::swift::metadata::visit(AG::swift::metadata_visitor&) const + 1244
21  AttributeGraph                       0x1b26972f0 AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode) + 580
22  AttributeGraph                       0x1b26976b4 AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int) + 344
23  AttributeGraph                       0x1b2696394 AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool) + 56
24  AttributeGraph                       0x1b2696238 AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long) + 120
25  AttributeGraph                       0x1b267f608 AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long) + 180
26  AttributeGraph                       0x1b267eb4c AG::swift::metadata::visit(AG::swift::metadata_visitor&) const + 1244
27  AttributeGraph                       0x1b26972f0 AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode) + 580
28  AttributeGraph                       0x1b26976b4 AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int) + 344
29  AttributeGraph                       0x1b2696394 AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool) + 56
30  AttributeGraph                       0x1b2696238 AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long) + 120
31  AttributeGraph                       0x1b267f608 AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long) + 180
32  AttributeGraph                       0x1b267eb4c AG::swift::metadata::visit(AG::swift::metadata_visitor&) const + 1244
33  AttributeGraph                       0x1b26972f0 AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode) + 580
34  AttributeGraph                       0x1b26976b4 AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int) + 344
35  AttributeGraph                       0x1b2696394 AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool) + 56
36  AttributeGraph                       0x1b2696238 AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long) + 120
37  AttributeGraph                       0x1b267f608 AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long) + 180
38  AttributeGraph                       0x1b267eb4c AG::swift::metadata::visit(AG::swift::metadata_visitor&) const + 1244
39  AttributeGraph                       0x1b26972f0 AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode) + 580
40  AttributeGraph                       0x1b2698b44 AG::(anonymous namespace)::TypeDescriptorCache::drain_queue(void*) + 348
41  libdispatch.dylib                   0x184f363e8 _dispatch_client_callout + 20
42  libdispatch.dylib                   0x184f48080 _dispatch_root_queue_drain + 864
43  libdispatch.dylib                   0x184f486b8 _dispatch_worker_thread2 + 156
44  libsystem_pthread.dylib             0x1850e2fd0 _pthread_wqthread + 228
45  libsystem_pthread.dylib             0x1850e1d28 start_wqthread + 8

Thread 3:
0   libsystem_pthread.dylib             0x1850e1d20 start_wqthread + 0


Thread 0 crashed with ARM Thread State (64-bit):
    x0: 0x0000600002175b08   x1: 0x0000000200000003   x2: 0xfffffffffffffff0   x3: 0x00006000022578f0
    x4: 0x00006000022578c0   x5: 0x0000000000000013   x6: 0x0000000000000020   x7: 0x0000000000000000
    x8: 0xfffffffe00000000   x9: 0x0000000200000003  x10: 0x0000000000000003  x11: 0x00000000a96037fb
   x12: 0x00000000000007fb  x13: 0x00000000000007fd  x14: 0x00000000a980383d  x15: 0x000000000000003d
   x16: 0x00000000a96037fb  x17: 0x0000000000003800  x18: 0x0000000000000000  x19: 0x0000000102af1efd
   x20: 0x0000600002175b00  x21: 0x0000000000000000  x22: 0x000000000000000b  x23: 0x000000000000002c
   x24: 0x000000000000000c  x25: 0x0000000102af1ed0  x26: 0xf0000000000000d3  x27: 0x0000000000000000
   x28: 0x000000016d40b4b0   fp: 0x000000016d40b140   lr: 0x0000000194dd8ee0
    sp: 0x000000016d40b070   pc: 0x0000000194dd8ee0 cpsr: 0x60001000
   far: 0x0000000000000000  esr: 0xf2000001 (Breakpoint) brk 1

Binary Images:
       0x103208000 -        0x103213fff libobjc-trampolines.dylib (*) <e8a1b184-0349-3c61-a119-6543eb038317> /usr/lib/libobjc-trampolines.dylib
       0x1034fc000 -        0x1036a3fff libllama.0.dylib (*) <524090b7-fd8d-3aa2-8fa0-849eedb49376> /Applications/Embershard.app/Contents/Frameworks/libllama.0.dylib
       0x1032b4000 -        0x1032bbfff libggml.0.dylib (*) <b8a6d338-564d-393b-95a5-43af5305cc73> /Applications/Embershard.app/Contents/Frameworks/libggml.0.dylib
       0x10339c000 -        0x1033bffff libggml-metal.0.dylib (*) <4499326b-003b-3adb-b897-6750fb5ac6f0> /Applications/Embershard.app/Contents/Frameworks/libggml-metal.0.dylib
       0x1032cc000 -        0x1032cffff libggml-blas.0.dylib (*) <7835653b-42e5-31bb-8241-7e7565726a1a> /Applications/Embershard.app/Contents/Frameworks/libggml-blas.0.dylib
       0x103840000 -        0x103907fff libggml-cpu.0.dylib (*) <1d6ba04d-0a07-33d3-8df8-c03165ecb90b> /Applications/Embershard.app/Contents/Frameworks/libggml-cpu.0.dylib
       0x103758000 -        0x1037effff libggml-base.0.dylib (*) <2fb8c943-5536-3fa7-afc6-0bb7febcbbf4> /Applications/Embershard.app/Contents/Frameworks/libggml-base.0.dylib
       0x1029e8000 -        0x102b27fff com.embershard.app (0.1.5) <91317060-f7c0-3330-82ac-c9bac230fa54> /Applications/Embershard.app/Contents/MacOS/Embershard
4d2751b5d729> /usr/lib/swift/libswiftCore.dylib
2e9123e81bf7> /usr/lib/system/libdispatch.dylib
b165c0d98534> /System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI
cb7c41ed853c> /System/Library/PrivateFrameworks/AttributeGraph.framework/Versions/A/AttributeGraph
da6c1d0fb53c> /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit
fb848c4f39df> /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
c8eacc5128e0> /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
0de48c174133> /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/AE.framework/Versions/A/AE
b8b492b0f506> /System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox
74bdc06b7828> /usr/lib/dyld
000000000000> ???
7776ac7ea2fa> /usr/lib/system/libsystem_pthread.dylib
0G(100%)
Writable regions: Total=737.2M written=0K(0%) resident=0K(0%) swapped_out=0K(0%) unallocated=737.2M(100%)

                                VIRTUAL   REGION
REGION TYPE                        SIZE    COUNT (non-coalesced)
===========                     =======  =======
Activity Tracing                   256K        1
AttributeGraph Data               1024K        1
ColorSync                          592K       27
CoreAnimation                      896K       56
CoreGraphics                        48K        3
CoreServices                        16K        1
Foundation                          16K        1
Kernel Alloc Once                   32K        1
MALLOC                           725.4M       42
MALLOC guard page                  288K       18
STACK GUARD                       56.1M        4
Stack                             9808K        4
VM_ALLOCATE                        192K       12
__AUTH                            1421K      258
__AUTH_CONST                      23.4M      441
__CTF                               824        1
__DATA                            10.9M      434
__DATA_CONST                      21.9M      452
__DATA_DIRTY                      1295K      138
__FONT_DATA                          4K        1
__LINKEDIT                       529.4M        9
__OBJC_RO                         71.7M        2
__OBJC_RW                         2195K        1
__TEXT                           539.1M      469
dyld private memory                272K        2
mapped file                      174.1M       26
shared memory                      848K       13
===========                     =======  =======
TOTAL                              2.1G     2418



-----------
Full Report
-----------

{"app_name":"Embershard","timestamp":"2026-06-17 18:01:13.00 +0200","app_version":"0.1.5","slice_uuid":"91317060-f7c0-3330-82ac-c9bac230fa54","build_version":"6","platform":1,"bundleID":"com.embershard.app","share_with_app_devs":0,"is_first_party":0,"bug_type":"309","os_version":"macOS 14.4 (23E214)","roots_installed":0,"name":"Embershard","incident_id":"2AD1AAD9-A4DB-4FB0-8560-B54DDE4221C3"}
{
  "uptime" : 8500,
  "procRole" : "Foreground",
  "version" : 2,
  "userID" : 501,
  "deployVersion" : 210,
  "modelCode" : "MacBookAir10,1",
  "coalitionID" : 2549,
  "osVersion" : {
    "train" : "macOS 14.4",
    "build" : "23E214",
    "releaseType" : "User"
  },
  "captureTime" : "2026-06-17 18:01:12.1271 +0200",
  "codeSigningMonitor" : 1,
  "incident" : "2AD1AAD9-A4DB-4FB0-8560-B54DDE4221C3",
  "pid" : 87144,
  "translated" : false,
  "cpuType" : "ARM-64",
  "roots_installed" : 0,
  "bug_type" : "309",
  "procLaunch" : "2026-06-17 18:01:10.5220 +0200",
  "procStartAbsTime" : 205671662788,
  "procExitAbsTime" : 205709748247,
  "procName" : "Embershard",
  "procPath" : "\/Applications\/Embershard.app\/Contents\/MacOS\/Embershard",
  "bundleInfo" : {"CFBundleShortVersionString":"0.1.5","CFBundleVersion":"6","CFBundleIdentifier":"com.embershard.app"},
  "storeInfo" : {"deviceIdentifierForVendor":"2EAE3C14-A5EB-5826-B361-B924DF99D502","thirdParty":true},
  "parentProc" : "launchd",
  "parentPid" : 1,
  "coalitionName" : "com.embershard.app",
  "crashReporterKey" : "32832412-6FE1-4CD1-572D-550BF2C85412",
  "codeSigningID" : "com.embershard.app",
  "codeSigningTeamID" : "",
  "codeSigningFlags" : 570425857,
  "codeSigningValidationCategory" : 10,
  "codeSigningTrustLevel" : 4294967295,
  "instructionByteStream" : {"beforePC":"4gMZquMDF6rkAxWq5QMTquYDFqrnAxiqFQCA0pYDAJTgAxSqazQPlA==","atPC":"IAAg1CgAgFKJEoBS6BMAuekHAPlIAIBS6AMAOSAnALAA0CeRIycAsA=="},
  "sip" : "enabled",
  "exception" : {"codes":"0x0000000000000001, 0x0000000194dd8ee0","rawCodes":[1,6792515296],"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},
  "termination" : {"flags":0,"code":5,"namespace":"SIGNAL","indicator":"Trace\/BPT trap: 5","byProc":"exc handler","byPid":87144},
  "os_fault" : {"process":"Embershard"},
  "extMods" : {"caller":{"thread_create":0,"thread_set_state":0,"task_for_pid":0},"system":{"thread_create":0,"thread_set_state":0,"task_for_pid":0},"targeted":{"thread_create":0,"thread_set_state":0,"task_for_pid":0},"warnings":0},
  "faultingThread" : 0,
  "threads" : [{"triggered":true,"id":1306079,"threadState":{"x":[{"value":105553151351560},{"value":8589934595},{"value":18446744073709551600},{"value":105553152276720},{"value":105553152276672},{"value":19},{"value":32},{"value":0},{"value":18446744065119617024},{"value":8589934595},{"value":3},{"value":2841655291},{"value":2043},{"value":2045},{"value":2843752509},{"value":61},{"value":2841655291},{"value":14336},{"value":0},{"value":4339998461},{"value":105553151351552},{"value":0},{"value":11},{"value":44},{"value":12},{"value":4339998416},{"value":17293822569102704851},{"value":0},{"value":6127924400}],"flavor":"ARM_THREAD_STATE64","lr":{"value":6792515296},"cpsr":{"value":1610616832},"fp":{"value":6127923520},"sp":{"value":6127923312},"esr":{"value":4060086273,"description":"(Breakpoint) brk 1"},"pc":{"value":6792515296,"matchesCrashFrame":1},"far":{"value":0}},"queue":"com.apple.main-thread","frames":[{"imageOffset":237280,"symbol":"_assertionFailure(_:_:file:line:flags:)","symbolLocation":268,"imageIndex":8},{"imageOffset":995776,"symbol":"closure #1 in variable initialization expression of static NSBundle.module","symbolLocation":612,"imageIndex":7},{"imageOffset":995148,"symbol":"one-time initialization function for module","symbolLocation":12,"imageIndex":7},{"imageOffset":17384,"symbol":"_dispatch_client_callout","symbolLocation":20,"imageIndex":9},{"imageOffset":23656,"symbol":"_dispatch_once_callout","symbolLocation":32,"imageIndex":9},{"imageOffset":236400,"symbol":"specialized WelcomeView.logoImage.getter","symbolLocation":424,"imageIndex":7},{"imageOffset":208380,"symbol":"closure #1 in closure #1 in WelcomeView.body.getter","symbolLocation":228,"imageIndex":7},{"imageOffset":206512,"symbol":"closure #1 in WelcomeView.body.getter","symbolLocation":96,"imageIndex":7},{"imageOffset":205992,"symbol":"WelcomeView.body.getter","symbolLocation":96,"imageIndex":7},{"imageOffset":7961888,"imageIndex":10},{"imageOffset":24200128,"imageIndex":10},{"imageOffset":24198900,"imageIndex":10},{"imageOffset":1185136,"imageIndex":10},{"imageOffset":46528,"symbol":"AG::Graph::UpdateStack::update()","symbolLocation":512,"imageIndex":11},{"imageOffset":48636,"symbol":"AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int)","symbolLocation":424,"imageIndex":11},{"imageOffset":84040,"symbol":"AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long)","symbolLocation":720,"imageIndex":11},{"imageOffset":183500,"symbol":"AGGraphGetValue","symbolLocation":228,"imageIndex":11},{"imageOffset":3378500,"imageIndex":10},{"imageOffset":4935216,"imageIndex":10},{"imageOffset":46528,"symbol":"AG::Graph::UpdateStack::update()","symbolLocation":512,"imageIndex":11},{"imageOffset":48636,"symbol":"AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int)","symbolLocation":424,"imageIndex":11},{"imageOffset":84040,"symbol":"AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long)","symbolLocation":720,"imageIndex":11},{"imageOffset":182908,"symbol":"AGGraphGetInputValue","symbolLocation":248,"imageIndex":11},{"imageOffset":13714544,"imageIndex":10},{"imageOffset":3615796,"imageIndex":10},{"imageOffset":5020380,"imageIndex":10},{"imageOffset":17639784,"imageIndex":10},{"imageOffset":2723904,"imageIndex":10},{"imageOffset":4935324,"imageIndex":10},{"imageOffset":46528,"symbol":"AG::Graph::UpdateStack::update()","symbolLocation":512,"imageIndex":11},{"imageOffset":48636,"symbol":"AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int)","symbolLocation":424,"imageIndex":11},{"imageOffset":84040,"symbol":"AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long)","symbolLocation":720,"imageIndex":11},{"imageOffset":182908,"symbol":"AGGraphGetInputValue","symbolLocation":248,"imageIndex":11},{"imageOffset":13714544,"imageIndex":10},{"imageOffset":3615796,"imageIndex":10},{"imageOffset":5020380,"imageIndex":10},{"imageOffset":17639784,"imageIndex":10},{"imageOffset":2723904,"imageIndex":10},{"imageOffset":4935324,"imageIndex":10},{"imageOffset":46528,"symbol":"AG::Graph::UpdateStack::update()","symbolLocation":512,"imageIndex":11},{"imageOffset":48636,"symbol":"AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int)","symbolLocation":424,"imageIndex":11},{"imageOffset":83560,"symbol":"AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long)","symbolLocation":240,"imageIndex":11},{"imageOffset":182908,"symbol":"AGGraphGetInputValue","symbolLocation":248,"imageIndex":11},{"imageOffset":11020064,"imageIndex":10},{"imageOffset":15690864,"imageIndex":10},{"imageOffset":15588536,"imageIndex":10},{"imageOffset":15588156,"imageIndex":10},{"imageOffset":15587296,"imageIndex":10},{"imageOffset":25218796,"imageIndex":10},{"imageOffset":21819700,"imageIndex":10},{"imageOffset":15588536,"imageIndex":10},{"imageOffset":15588156,"imageIndex":10},{"imageOffset":15587296,"imageIndex":10},{"imageOffset":25218796,"imageIndex":10},{"imageOffset":10540636,"imageIndex":10},{"imageOffset":18921396,"imageIndex":10},{"imageOffset":18920832,"imageIndex":10},{"imageOffset":25218796,"imageIndex":10},{"imageOffset":13723508,"imageIndex":10},{"imageOffset":13726640,"imageIndex":10},{"imageOffset":13717540,"imageIndex":10},{"imageOffset":12706600,"imageIndex":10},{"imageOffset":12708440,"imageIndex":10},{"imageOffset":18921396,"imageIndex":10},{"imageOffset":18920832,"imageIndex":10},{"imageOffset":25218796,"imageIndex":10},{"imageOffset":23972192,"imageIndex":10},{"imageOffset":23974860,"imageIndex":10},{"imageOffset":15588536,"imageIndex":10},{"imageOffset":15588156,"imageIndex":10},{"imageOffset":15587296,"imageIndex":10},{"imageOffset":25218796,"imageIndex":10},{"imageOffset":13316316,"imageIndex":10},{"imageOffset":6661328,"imageIndex":10},{"imageOffset":46528,"symbol":"AG::Graph::UpdateStack::update()","symbolLocation":512,"imageIndex":11},{"imageOffset":48636,"symbol":"AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int)","symbolLocation":424,"imageIndex":11},{"imageOffset":84040,"symbol":"AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long)","symbolLocation":720,"imageIndex":11},{"imageOffset":183500,"symbol":"AGGraphGetValue","symbolLocation":228,"imageIndex":11},{"imageOffset":6492796,"imageIndex":10},{"imageOffset":6661328,"imageIndex":10},{"imageOffset":46528,"symbol":"AG::Graph::UpdateStack::update()","symbolLocation":512,"imageIndex":11},{"imageOffset":48636,"symbol":"AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int)","symbolLocation":424,"imageIndex":11},{"imageOffset":84040,"symbol":"AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long)","symbolLocation":720,"imageIndex":11},{"imageOffset":183500,"symbol":"AGGraphGetValue","symbolLocation":228,"imageIndex":11},{"imageOffset":6647472,"imageIndex":10},{"imageOffset":46528,"symbol":"AG::Graph::UpdateStack::update()","symbolLocation":512,"imageIndex":11},{"imageOffset":48636,"symbol":"AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int)","symbolLocation":424,"imageIndex":11},{"imageOffset":84040,"symbol":"AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long)","symbolLocation":720,"imageIndex":11},{"imageOffset":183500,"symbol":"AGGraphGetValue","symbolLocation":228,"imageIndex":11},{"imageOffset":6027484,"imageIndex":10},{"imageOffset":4985736,"imageIndex":10},{"imageOffset":46528,"symbol":"AG::Graph::UpdateStack::update()","symbolLocation":512,"imageIndex":11},{"imageOffset":48636,"symbol":"AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int)","symbolLocation":424,"imageIndex":11},{"imageOffset":84040,"symbol":"AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long)","symbolLocation":720,"imageIndex":11},{"imageOffset":183500,"symbol":"AGGraphGetValue","symbolLocation":228,"imageIndex":11},{"imageOffset":23624200,"imageIndex":10},{"imageOffset":4976712,"imageIndex":10},{"imageOffset":46528,"symbol":"AG::Graph::UpdateStack::update()","symbolLocation":512,"imageIndex":11},{"imageOffset":48636,"symbol":"AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int)","symbolLocation":424,"imageIndex":11},{"imageOffset":108460,"symbol":"AG::Subgraph::update(unsigned int)","symbolLocation":848,"imageIndex":11},{"imageOffset":13306224,"imageIndex":10},{"imageOffset":23765496,"imageIndex":10},{"imageOffset":23763840,"imageIndex":10},{"imageOffset":23750952,"imageIndex":10},{"imageOffset":25795312,"imageIndex":10},{"imageOffset":13400440,"imageIndex":10},{"imageOffset":13398356,"imageIndex":10},{"imageOffset":13395096,"imageIndex":10},{"imageOffset":13394628,"imageIndex":10},{"imageOffset":4297524,"imageIndex":10},{"imageOffset":4238088,"imageIndex":10},{"imageOffset":4944416,"imageIndex":10},{"imageOffset":46528,"symbol":"AG::Graph::UpdateStack::update()","symbolLocation":512,"imageIndex":11},{"imageOffset":48636,"symbol":"AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int)","symbolLocation":424,"imageIndex":11},{"imageOffset":84040,"symbol":"AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long)","symbolLocation":720,"imageIndex":11},{"imageOffset":183500,"symbol":"AGGraphGetValue","symbolLocation":228,"imageIndex":11},{"imageOffset":4338556,"imageIndex":10},{"imageOffset":4944300,"imageIndex":10},{"imageOffset":46528,"symbol":"AG::Graph::UpdateStack::update()","symbolLocation":512,"imageIndex":11},{"imageOffset":48636,"symbol":"AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int)","symbolLocation":424,"imageIndex":11},{"imageOffset":83560,"symbol":"AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long)","symbolLocation":240,"imageIndex":11},{"imageOffset":182908,"symbol":"AGGraphGetInputValue","symbolLocation":248,"imageIndex":11},{"imageOffset":11020064,"imageIndex":10},{"imageOffset":20650956,"imageIndex":10},{"imageOffset":15588536,"imageIndex":10},{"imageOffset":15588156,"imageIndex":10},{"imageOffset":15588592,"imageIndex":10},{"imageOffset":25218796,"imageIndex":10},{"imageOffset":23972192,"imageIndex":10},{"imageOffset":23974860,"imageIndex":10},{"imageOffset":15588536,"imageIndex":10},{"imageOffset":15588156,"imageIndex":10},{"imageOffset":15587296,"imageIndex":10},{"imageOffset":25218796,"imageIndex":10},{"imageOffset":23972192,"imageIndex":10},{"imageOffset":23974860,"imageIndex":10},{"imageOffset":15588536,"imageIndex":10},{"imageOffset":15588156,"imageIndex":10},{"imageOffset":15587296,"imageIndex":10},{"imageOffset":25218796,"imageIndex":10},{"imageOffset":13311616,"imageIndex":10},{"imageOffset":23767220,"imageIndex":10},{"imageOffset":23759588,"imageIndex":10},{"imageOffset":23753744,"imageIndex":10},{"imageOffset":23750540,"imageIndex":10},{"imageOffset":15091008,"imageIndex":10},{"imageOffset":14041328,"imageIndex":10},{"imageOffset":14041820,"imageIndex":10},{"imageOffset":320684,"symbol":"-[NSView _setWindow:]","symbolLocation":1788,"imageIndex":12},{"imageOffset":351164,"symbol":"-[NSView addSubview:]","symbolLocation":212,"imageIndex":12},{"imageOffset":374420,"symbol":"-[NSFrameView addSubview:]","symbolLocation":52,"imageIndex":12},{"imageOffset":374344,"symbol":"-[NSThemeFrame addSubview:]","symbolLocation":456,"imageIndex":12},{"imageOffset":372840,"symbol":"-[NSView addSubview:positioned:relativeTo:]","symbolLocation":372,"imageIndex":12},{"imageOffset":372336,"symbol":"-[NSThemeFrame addSubview:positioned:relativeTo:]","symbolLocation":52,"imageIndex":12},{"imageOffset":372260,"symbol":"-[NSThemeFrame _addKnownSubview:positioned:relativeTo:]","symbolLocation":44,"imageIndex":12},{"imageOffset":480736,"symbol":"-[NSWindow setContentView:]","symbolLocation":292,"imageIndex":12},{"imageOffset":2141560,"symbol":"-[NSWindow _contentViewControllerChanged]","symbolLocation":364,"imageIndex":12},{"imageOffset":509468,"symbol":"NSPerformVisuallyAtomicChange","symbolLocation":108,"imageIndex":12},{"imageOffset":2141080,"symbol":"-[NSWindow setContentViewController:]","symbolLocation":132,"imageIndex":12},{"imageOffset":15078668,"imageIndex":10},{"imageOffset":8122436,"imageIndex":10},{"imageOffset":8124464,"imageIndex":10},{"imageOffset":10895364,"imageIndex":10},{"imageOffset":15058260,"imageIndex":10},{"imageOffset":15042648,"imageIndex":10},{"imageOffset":15037896,"imageIndex":10},{"imageOffset":22559492,"imageIndex":10},{"imageOffset":22560316,"imageIndex":10},{"imageOffset":469788,"symbol":"__CFNOTIFICATIONCENTER_IS_CALLING_OUT_TO_AN_OBSERVER__","symbolLocation":148,"imageIndex":13},{"imageOffset":1076664,"symbol":"___CFXRegistrationPost_block_invoke","symbolLocation":88,"imageIndex":13},{"imageOffset":1076480,"symbol":"_CFXRegistrationPost","symbolLocation":440,"imageIndex":13},{"imageOffset":267848,"symbol":"_CFXNotificationPost","symbolLocation":768,"imageIndex":13},{"imageOffset":37988,"symbol":"-[NSNotificationCenter postNotificationName:object:userInfo:]","symbolLocation":88,"imageIndex":14},{"imageOffset":271228,"symbol":"-[NSApplication _postDidFinishNotification]","symbolLocation":284,"imageIndex":12},{"imageOffset":270636,"symbol":"-[NSApplication _sendFinishLaunchingNotification]","symbolLocation":172,"imageIndex":12},{"imageOffset":263796,"symbol":"-[NSApplication(NSAppleEventHandling) _handleAEOpenEvent:]","symbolLocation":504,"imageIndex":12},{"imageOffset":262768,"symbol":"-[NSApplication(NSAppleEventHandling) _handleCoreEvent:withReplyEvent:]","symbolLocation":492,"imageIndex":12},{"imageOffset":203028,"symbol":"-[NSAppleEventManager dispatchRawAppleEvent:withRawReply:handlerRefCon:]","symbolLocation":316,"imageIndex":14},{"imageOffset":202504,"symbol":"_NSAppleEventManagerGenericHandler","symbolLocation":80,"imageIndex":14},{"imageOffset":47556,"imageIndex":15},{"imageOffset":45804,"imageIndex":15},{"imageOffset":18600,"symbol":"aeProcessAppleEvent","symbolLocation":488,"imageIndex":15},{"imageOffset":274064,"symbol":"AEProcessAppleEvent","symbolLocation":68,"imageIndex":16},{"imageOffset":240764,"symbol":"_DPSNextEvent","symbolLocation":1440,"imageIndex":12},{"imageOffset":8572396,"symbol":"-[NSApplication(NSEventRouting) _nextEventMatchingEventMask:untilDate:inMode:dequeue:]","symbolLocation":700,"imageIndex":12},{"imageOffset":187576,"symbol":"-[NSApplication run]","symbolLocation":476,"imageIndex":12},{"imageOffset":20308,"symbol":"NSApplicationMain","symbolLocation":880,"imageIndex":12},{"imageOffset":1090016,"imageIndex":10},{"imageOffset":8845548,"imageIndex":10},{"imageOffset":13015644,"imageIndex":10},{"imageOffset":372244,"symbol":"EmberShardApp_main","symbolLocation":64,"imageIndex":7},{"imageOffset":24800,"symbol":"start","symbolLocation":2360,"imageIndex":17}]},{"id":1306294,"frames":[{"imageOffset":7456,"symbol":"start_wqthread","symbolLocation":0,"imageIndex":19}],"threadState":{"x":[{"value":6128529408},{"value":5891},{"value":6127992832},{"value":0},{"value":409602},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":4096},"fp":{"value":0},"sp":{"value":6128529408},"esr":{"value":1442840704,"description":" Address size fault"},"pc":{"value":6527261984},"far":{"value":0}}},{"id":1306296,"threadState":{"x":[{"value":6129098592},{"value":4339957488,"symbolLocation":0,"symbol":"protocol conformance descriptor for MacHelperChatView.Decision"},{"value":0},{"value":0},{"value":6797768580,"symbolLocation":0,"symbol":"protocol descriptor for Equatable"},{"value":6523800112,"symbolLocation":0,"symbol":"dyld4::APIs::_dyld_find_protocol_conformance_on_disk(void const*, void const*, void const*, unsigned int)"},{"value":8347862776,"symbolLocation":928,"symbol":"vtable for dyld4::APIs"},{"value":1632},{"value":4340243512,"symbolLocation":128,"symbol":"full type metadata for FileResults"},{"value":286025},{"value":6129098486},{"value":0},{"value":1},{"value":0},{"value":7286225925},{"value":5252438128},{"value":6797768580,"symbolLocation":0,"symbol":"protocol descriptor for Equatable"},{"value":59657},{"value":0},{"value":6129098592},{"value":4339957488,"symbolLocation":0,"symbol":"protocol conformance descriptor for MacHelperChatView.Decision"},{"value":6129098488},{"value":6129098496},{"value":6129098487},{"value":6129098472},{"value":6129098512},{"value":5240803288},{"value":4340185208},{"value":4340184976}],"flavor":"ARM_THREAD_STATE64","lr":{"value":5778399803689504684},"cpsr":{"value":2147487744},"fp":{"value":6129098336},"sp":{"value":6129098224},"esr":{"value":2449473543,"description":"(Data Abort) byte read Translation fault"},"pc":{"value":6796451476},"far":{"value":0}},"queue":"com.apple.root.utility-qos","frames":[{"imageOffset":4173460,"symbol":"swift_conformsToProtocolMaybeInstantiateSuperclasses(swift::TargetMetadata<swift::InProcess> const*, swift::TargetProtocolDescriptor<swift::InProcess> const*, bool)::$_8::operator()((anonymous namespace)::ConformanceSection const&) const::'lambda'(swift::TargetProtocolConformanceDescriptor<swift::InProcess> const&)::operator()(swift::TargetProtocolConformanceDescriptor<swift::InProcess> const&) const","symbolLocation":100,"imageIndex":8},{"imageOffset":4169644,"symbol":"swift_conformsToProtocolMaybeInstantiateSuperclasses(swift::TargetMetadata<swift::InProcess> const*, swift::TargetProtocolDescriptor<swift::InProcess> const*, bool)","symbolLocation":3948,"imageIndex":8},{"imageOffset":4161900,"symbol":"swift_conformsToProtocol","symbolLocation":156,"imageIndex":8},{"imageOffset":131428,"symbol":"AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode)","symbolLocation":184,"imageIndex":11},{"imageOffset":132788,"symbol":"AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int)","symbolLocation":344,"imageIndex":11},{"imageOffset":127892,"symbol":"AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool)","symbolLocation":56,"imageIndex":11},{"imageOffset":127544,"symbol":"AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long)","symbolLocation":120,"imageIndex":11},{"imageOffset":34312,"symbol":"AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long)","symbolLocation":180,"imageIndex":11},{"imageOffset":31564,"symbol":"AG::swift::metadata::visit(AG::swift::metadata_visitor&) const","symbolLocation":1244,"imageIndex":11},{"imageOffset":131824,"symbol":"AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode)","symbolLocation":580,"imageIndex":11},{"imageOffset":132788,"symbol":"AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int)","symbolLocation":344,"imageIndex":11},{"imageOffset":127892,"symbol":"AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool)","symbolLocation":56,"imageIndex":11},{"imageOffset":127544,"symbol":"AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long)","symbolLocation":120,"imageIndex":11},{"imageOffset":34312,"symbol":"AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long)","symbolLocation":180,"imageIndex":11},{"imageOffset":31564,"symbol":"AG::swift::metadata::visit(AG::swift::metadata_visitor&) const","symbolLocation":1244,"imageIndex":11},{"imageOffset":131824,"symbol":"AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode)","symbolLocation":580,"imageIndex":11},{"imageOffset":132788,"symbol":"AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int)","symbolLocation":344,"imageIndex":11},{"imageOffset":127892,"symbol":"AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool)","symbolLocation":56,"imageIndex":11},{"imageOffset":127544,"symbol":"AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long)","symbolLocation":120,"imageIndex":11},{"imageOffset":34312,"symbol":"AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long)","symbolLocation":180,"imageIndex":11},{"imageOffset":31564,"symbol":"AG::swift::metadata::visit(AG::swift::metadata_visitor&) const","symbolLocation":1244,"imageIndex":11},{"imageOffset":131824,"symbol":"AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode)","symbolLocation":580,"imageIndex":11},{"imageOffset":132788,"symbol":"AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int)","symbolLocation":344,"imageIndex":11},{"imageOffset":127892,"symbol":"AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool)","symbolLocation":56,"imageIndex":11},{"imageOffset":127544,"symbol":"AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long)","symbolLocation":120,"imageIndex":11},{"imageOffset":34312,"symbol":"AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long)","symbolLocation":180,"imageIndex":11},{"imageOffset":31564,"symbol":"AG::swift::metadata::visit(AG::swift::metadata_visitor&) const","symbolLocation":1244,"imageIndex":11},{"imageOffset":131824,"symbol":"AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode)","symbolLocation":580,"imageIndex":11},{"imageOffset":132788,"symbol":"AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int)","symbolLocation":344,"imageIndex":11},{"imageOffset":127892,"symbol":"AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool)","symbolLocation":56,"imageIndex":11},{"imageOffset":127544,"symbol":"AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long)","symbolLocation":120,"imageIndex":11},{"imageOffset":34312,"symbol":"AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long)","symbolLocation":180,"imageIndex":11},{"imageOffset":31564,"symbol":"AG::swift::metadata::visit(AG::swift::metadata_visitor&) const","symbolLocation":1244,"imageIndex":11},{"imageOffset":131824,"symbol":"AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode)","symbolLocation":580,"imageIndex":11},{"imageOffset":132788,"symbol":"AG::(anonymous namespace)::TypeDescriptorCache::fetch(AG::swift::metadata const*, unsigned int, AG::LayoutDescriptor::HeapMode, int)","symbolLocation":344,"imageIndex":11},{"imageOffset":127892,"symbol":"AG::LayoutDescriptor::Builder::should_visit_fields(AG::swift::metadata const*, bool)","symbolLocation":56,"imageIndex":11},{"imageOffset":127544,"symbol":"AG::LayoutDescriptor::Builder::visit_element(AG::swift::metadata const*, AG::swift::metadata::ref_kind, unsigned long, unsigned long)","symbolLocation":120,"imageIndex":11},{"imageOffset":34312,"symbol":"AG::swift::metadata_visitor::visit_field(AG::swift::metadata const*, AG::swift::field_record const&, unsigned long, unsigned long)","symbolLocation":180,"imageIndex":11},{"imageOffset":31564,"symbol":"AG::swift::metadata::visit(AG::swift::metadata_visitor&) const","symbolLocation":1244,"imageIndex":11},{"imageOffset":131824,"symbol":"AG::LayoutDescriptor::make_layout(AG::swift::metadata const*, AGComparisonMode, AG::LayoutDescriptor::HeapMode)","symbolLocation":580,"imageIndex":11},{"imageOffset":138052,"symbol":"AG::(anonymous namespace)::TypeDescriptorCache::drain_queue(void*)","symbolLocation":348,"imageIndex":11},{"imageOffset":17384,"symbol":"_dispatch_client_callout","symbolLocation":20,"imageIndex":9},{"imageOffset":90240,"symbol":"_dispatch_root_queue_drain","symbolLocation":864,"imageIndex":9},{"imageOffset":91832,"symbol":"_dispatch_worker_thread2","symbolLocation":156,"imageIndex":9},{"imageOffset":12240,"symbol":"_pthread_wqthread","symbolLocation":228,"imageIndex":19},{"imageOffset":7464,"symbol":"start_wqthread","symbolLocation":8,"imageIndex":19}]},{"id":1306297,"frames":[{"imageOffset":7456,"symbol":"start_wqthread","symbolLocation":0,"imageIndex":19}],"threadState":{"x":[{"value":6129676288},{"value":8707},{"value":6129139712},{"value":0},{"value":409603},{"value":18446744073709551615},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0},{"value":0}],"flavor":"ARM_THREAD_STATE64","lr":{"value":0},"cpsr":{"value":4096},"fp":{"value":0},"sp":{"value":6129676288},"esr":{"value":1442840704,"description":" Address size fault"},"pc":{"value":6527261984},"far":{"value":0}}}],
  "usedImages" : [
  {
    "source" : "P",
    "arch" : "arm64e",
    "base" : 4347428864,
    "size" : 49152,
    "uuid" : "e8a1b184-0349-3c61-a119-6543eb038317",
    "path" : "\/usr\/lib\/libobjc-trampolines.dylib",
    "name" : "libobjc-trampolines.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4350525440,
    "size" : 1736704,
    "uuid" : "524090b7-fd8d-3aa2-8fa0-849eedb49376",
    "path" : "\/Applications\/Embershard.app\/Contents\/Frameworks\/libllama.0.dylib",
    "name" : "libllama.0.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4348133376,
    "size" : 32768,
    "uuid" : "b8a6d338-564d-393b-95a5-43af5305cc73",
    "path" : "\/Applications\/Embershard.app\/Contents\/Frameworks\/libggml.0.dylib",
    "name" : "libggml.0.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4349083648,
    "size" : 147456,
    "uuid" : "4499326b-003b-3adb-b897-6750fb5ac6f0",
    "path" : "\/Applications\/Embershard.app\/Contents\/Frameworks\/libggml-metal.0.dylib",
    "name" : "libggml-metal.0.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4348231680,
    "size" : 16384,
    "uuid" : "7835653b-42e5-31bb-8241-7e7565726a1a",
    "path" : "\/Applications\/Embershard.app\/Contents\/Frameworks\/libggml-blas.0.dylib",
    "name" : "libggml-blas.0.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4353949696,
    "size" : 819200,
    "uuid" : "1d6ba04d-0a07-33d3-8df8-c03165ecb90b",
    "path" : "\/Applications\/Embershard.app\/Contents\/Frameworks\/libggml-cpu.0.dylib",
    "name" : "libggml-cpu.0.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4352999424,
    "size" : 622592,
    "uuid" : "2fb8c943-5536-3fa7-afc6-0bb7febcbbf4",
    "path" : "\/Applications\/Embershard.app\/Contents\/Frameworks\/libggml-base.0.dylib",
    "name" : "libggml-base.0.dylib"
  },
  {
    "source" : "P",
    "arch" : "arm64",
    "base" : 4338909184,
    "CFBundleShortVersionString" : "0.1.5",
    "CFBundleIdentifier" : "com.embershard.app",
    "size" : 1310720,
    "uuid" : "91317060-f7c0-3330-82ac-c9bac230fa54",
    "path" : "\/Applications\/Embershard.app\/Contents\/MacOS\/Embershard",
    "name" : "Embershard",
    "CFBundleVersion" : "6"
4d2751b5d729",
libswiftCore.dylib",
2e9123e81bf7",
libdispatch.dylib",
b165c0d98534",
    "path" : "\/System\/Library\/Frameworks\/SwiftUI.framework\/Versions\/A\/SwiftUI",
cb7c41ed853c",
    "path" : "\/System\/Library\/PrivateFrameworks\/AttributeGraph.framework\/Versions\/A\/AttributeGraph",
da6c1d0fb53c",
    "path" : "\/System\/Library\/Frameworks\/AppKit.framework\/Versions\/C\/AppKit",
fb848c4f39df",
    "path" : "\/System\/Library\/Frameworks\/CoreFoundation.framework\/Versions\/A\/CoreFoundation",
c8eacc5128e0",
    "path" : "\/System\/Library\/Frameworks\/Foundation.framework\/Versions\/C\/Foundation",
0de48c174133",
    "path" : "\/System\/Library\/Frameworks\/CoreServices.framework\/Versions\/A\/Frameworks\/AE.framework\/Versions\/A\/AE",
b8b492b0f506",
    "path" : "\/System\/Library\/Frameworks\/Carbon.framework\/Versions\/A\/Frameworks\/HIToolbox.framework\/Versions\/A\/HIToolbox",
74bdc06b7828",
000000000000"
7776ac7ea2fa",
libsystem_pthread.dylib",
589aa9bf8fd2"
},
  "vmSummary" : "ReadOnly portion of Libraries: Total=1.0G resident=0K(0%) swapped_out_or_unallocated=1.0G(100%)\nWritable regions: Total=737.2M written=0K(0%) resident=0K(0%) swapped_out=0K(0%) unallocated=737.2M(100%)\n\n                                VIRTUAL   REGION \nREGION TYPE                        SIZE    COUNT (non-coalesced) \n===========                     =======  ======= \nActivity Tracing                   256K        1 \nAttributeGraph Data               1024K        1 \nColorSync                          592K       27 \nCoreAnimation                      896K       56 \nCoreGraphics                        48K        3 \nCoreServices                        16K        1 \nFoundation                          16K        1 \nKernel Alloc Once                   32K        1 \nMALLOC                           725.4M       42 \nMALLOC guard page                  288K       18 \nSTACK GUARD                       56.1M        4 \nStack                             9808K        4 \nVM_ALLOCATE                        192K       12 \n__AUTH                            1421K      258 \n__AUTH_CONST                      23.4M      441 \n__CTF                               824        1 \n__DATA                            10.9M      434 \n__DATA_CONST                      21.9M      452 \n__DATA_DIRTY                      1295K      138 \n__FONT_DATA                          4K        1 \n__LINKEDIT                       529.4M        9 \n__OBJC_RO                         71.7M        2 \n__OBJC_RW                         2195K        1 \n__TEXT                           539.1M      469 \ndyld private memory                272K        2 \nmapped file                      174.1M       26 \nshared memory                      848K       13 \n===========                     =======  ======= \nTOTAL                              2.1G     2418 \n",
  "legacyInfo" : {
  "threadTriggered" : {
    "queue" : "com.apple.main-thread"
  }
},
  "logWritingSignature" : "90978ecfa4ae11303d2c6f108d595c53f9928b3f",