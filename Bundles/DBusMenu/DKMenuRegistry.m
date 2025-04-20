/** A registry object for exporting the main menu to D-Bus
   Copyright (C) 2013 Free Software Foundation, Inc.

   Written by:  Niels Grewe <niels.grewe@halbordnung.de>
   Created: December 2013

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

   <title>DKMenuRegistry reference</title>
   */

#import <Foundation/NSObject.h>
#import "DKMenuRegistry.h"
#import <Foundation/NSIndexSet.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSWindow.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <DBusKit/DBusKit.h>
#import "com_canonical_AppMenu_Registrar.h"
#import "DKMenuProxy.h"
@interface NSObject (PrivateStuffDoNotUse)
- (id) _objectPathNodeAtPath: (NSString*)string;
- (void)_setObject: (id)obj atPath: (NSString*)path; 
@end

@interface DKProxy (PrivateStuffDoNotUse)
- (BOOL)_loadIntrospectionFromFile: (NSString*)path;
@end


@implementation DKMenuRegistry

- (id)init
{
  DKPort *sp = [[[DKPort alloc] initWithRemote: @"com.canonical.AppMenu.Registrar"] autorelease];
  NSConnection *connection = [NSConnection connectionWithReceivePort: [DKPort port]
                                                            sendPort: sp];
  if (nil == (self = [super init]))
  {
    return nil;
  }
  registrar = [(id)[connection proxyAtPath: @"/com/canonical/AppMenu/Registrar"] retain];

  if (nil == registrar)
  {
    NSDebugMLLog(@"DKMenu", @"No connection to menu server.");
    [self release];
    return nil;
  }

  windowNumbers = [NSMutableIndexSet new];
  return self;
}

- (void)dealloc
{
  [registrar release];
  [windowNumbers release];
  [busProxy release];
  [menuProxy release];
  [super dealloc];
}


- (DKProxy*)busProxy
{
  return busProxy;
}

+ (id)sharedRegistry
{
  // TODO: Actually make it a singleton
  return [self new];
}

- (void)_safeRegisterWindow:(NSDictionary *)args
{
  NSWindow *window = [args objectForKey:@"window"];
  int internalNumber = [window windowNumber];
  GSDisplayServer *srv = GSServerForWindow(window);
  uint32_t number = (uint32_t)(uintptr_t)[srv windowDevice: internalNumber];
  NSNumber *boxed = [NSNumber numberWithInt: number];

  if ((NO == [windowNumbers containsIndex: number]))
  {
    NSDebugMLLog(@"DKMenu", @"(Deferred) Publishing menu for window %d", number);
    [registrar RegisterWindow: boxed : busProxy];
    [windowNumbers addIndex: number];
  }
}

- (void)setupProxyForMenu: (NSMenu*)menu
{
  menuProxy = [[DKMenuProxy alloc] initWithMenu: menu];
  DKPort *p = (DKPort*)[DKPort port];
  // WARNING: This is not a public API. Don't use it.
  [p _setObject: menuProxy atPath: @"/org/gnustep/application/mainMenu"];
  busProxy = [p _objectPathNodeAtPath: @"/org/gnustep/application/mainMenu"]; 
  [menuProxy setExported: YES];
  NSBundle *bundle = [NSBundle bundleForClass: [self class]];
  NSString *path = [bundle pathForResource: @"com.canonical.dbusmenu"
                                    ofType: @"xml"];
  [busProxy _loadIntrospectionFromFile: path];
}

- (void)setMenu: (NSMenu*)menu forWindow: (NSWindow*)window
{
  if (nil == menuProxy)
  {
    [self setupProxyForMenu: menu];
  }
  else
  {
    NSDictionary *args = @{ @"window": window };
    [[NSRunLoop currentRunLoop] performSelector:@selector(_safeRegisterWindow:)
                                         target:self
                                       argument:args
                                          order:0
                                          modes:@[NSDefaultRunLoopMode]];
    return;
  }

  // First window logic continues here...
  int internalNumber = [window windowNumber];
  GSDisplayServer *srv = GSServerForWindow(window);
  uint32_t number = (uint32_t)(uintptr_t)[srv windowDevice: internalNumber];
  NSNumber *boxed = [NSNumber numberWithInt: number];
  if ((NO == [windowNumbers containsIndex: number]))
  {
    NSDebugMLLog(@"DKMenu", @"Publishing menu for window %d", number);
    [registrar RegisterWindow: boxed : busProxy];
    [windowNumbers addIndex: number];
  }
}
@end
