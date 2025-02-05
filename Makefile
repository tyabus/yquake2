# ------------------------------------------------------ #
# Makefile for the "Yamagi Quake 2 Client"               #
#                                                        #
# Just type "make" to compile the                        #
#  - Client (quake2)                                     #
#  - Server (q2ded)                                      #
#  - Quake II Game (baseq2)                              #
#  - Renderer libraries (gl, soft)                       #
#                                                        #
# Base dependencies:                                     #
#  - SDL 2.0                                             #
#  - libGL                                               #
#                                                        #
# Optional dependencies:                                 #
#  - OpenAL                                              #
#                                                        #
# Platforms:                                             #
#  - FreeBSD                                             #
#  - Linux                                               #
#  - OpenBSD                                             #
#  - OS X                                                #
#  - Windows (MinGW)                                     #
# ------------------------------------------------------ #

# User configurable options
# -------------------------

# Enables the optional OpenAL sound system.
# To use it your system needs libopenal.so.1
# or openal32.dll (we recommend openal-soft)
# installed
WITH_OPENAL:=yes

# Enable systemwide installation of game assets
WITH_SYSTEMWIDE:=no

# This will set the default SYSTEMDIR, a non-empty string
# would actually be used. On Windows normals slashes (/)
# instead of backslashed (\) should be used! The string
# MUST NOT be surrounded by quotation marks!
WITH_SYSTEMDIR:=""

# This will set the architectures of the OSX-binaries.
# You have to make sure your libs/frameworks supports
# these architectures! To build an universal ppc-compatible
# one would add -arch ppc for example.
OSX_ARCH:=-arch $(shell uname -m | sed -e s/i.86/i386/)

# This is an optional configuration file, it'll be used in
# case of presence.
CONFIG_FILE := config.mk

# ----------

# In case a of a configuration file being present, we'll just use it
ifeq ($(wildcard $(CONFIG_FILE)), $(CONFIG_FILE))
include $(CONFIG_FILE)
endif

# Detect the OS
ifdef SystemRoot
YQ2_OSTYPE := Windows
else
YQ2_OSTYPE ?= $(shell uname -s)
endif

# Special case for MinGW
ifneq (,$(findstring MINGW,$(YQ2_OSTYPE)))
YQ2_OSTYPE := Windows
endif

# Detect the architecture
ifeq ($(YQ2_OSTYPE), Windows)
ifdef PROCESSOR_ARCHITEW6432
# 64 bit Windows
YQ2_ARCH ?= $(PROCESSOR_ARCHITEW6432)
else
# 32 bit Windows
YQ2_ARCH ?= $(PROCESSOR_ARCHITECTURE)
endif
else
# Normalize some abiguous YQ2_ARCH strings
YQ2_ARCH ?= $(shell uname -m | sed -e 's/i.86/i386/' -e 's/amd64/x86_64/' -e 's/^arm.*/arm/')
endif

# On Windows / MinGW $(CC) is undefined by default.
ifeq ($(YQ2_OSTYPE),Windows)
CC := gcc
endif

# Detect the compiler
ifeq ($(shell $(CC) -v 2>&1 | grep -c "clang version"), 1)
COMPILER := clang
COMPILERVER := $(shell $(CC)  -dumpversion | sed -e 's/\.\([0-9][0-9]\)/\1/g' -e 's/\.\([0-9]\)/0\1/g' -e 's/^[0-9]\{3,4\}$$/&00/')
else ifeq ($(shell $(CC) -v 2>&1 | grep -c -E "(gcc version|gcc-Version)"), 1)
COMPILER := gcc
COMPILERVER := $(shell $(CC)  -dumpversion | sed -e 's/\.\([0-9][0-9]\)/\1/g' -e 's/\.\([0-9]\)/0\1/g' -e 's/^[0-9]\{3,4\}$$/&00/')
else
COMPILER := unknown
endif

# ----------

# Base CFLAGS.
#
# -O2 are enough optimizations.
#
# -fno-strict-aliasing since the source doesn't comply
#  with strict aliasing rules and it's next to impossible
#  to get it there...
#
# -fomit-frame-pointer since the framepointer is mostly
#  useless for debugging Quake II and slows things down.
#
# -g to build always with debug symbols. Please DO NOT
#  CHANGE THIS, since it's our only chance to debug this
#  crap when random crashes happen!
#
# -MMD to generate header dependencies.
#
# -fwrapv for defined integer wrapping. MSVC6 did this
#  and the game code requires it.
CFLAGS := -std=gnu99 -O2 -fno-strict-aliasing -Wall -pipe -g -ggdb -MMD -fwrapv

# ----------

# Switch of some annoying warnings.
ifeq ($(COMPILER), clang)
	# -Wno-missing-braces because otherwise clang complains
	#  about totally valid 'vec3_t bla = {0}' constructs.
	CFLAGS += -Wno-missing-braces
else ifeq ($(COMPILER), gcc)
	# GCC 8.0 or higher.
	ifeq ($(shell test $(COMPILERVER) -ge 80000; echo $$?),0)
	    # -Wno-format-truncation and -Wno-format-overflow
		# because GCC spams about 50 false positives.
    	CFLAGS += -Wno-format-truncation -Wno-format-overflow
	endif
endif

# ----------

# Defines the operating system and architecture
CFLAGS += -DYQ2OSTYPE=\"$(YQ2_OSTYPE)\" -DYQ2ARCH=\"$(YQ2_ARCH)\"

# ----------

# Fore reproduceable builds, look here for details:
# https://reproducible-builds.org/specs/source-date-epoch/
ifdef SOURCE_DATE_EPOCH
CFLAGS += -DBUILD_DATE=\"$(shell date --utc --date="@${SOURCE_DATE_EPOCH}" +"%b %_d %Y" | sed -e 's/ /\\ /g')\"
endif

# ----------

# If we're building with gcc for i386 let's define -ffloat-store.
# This helps the old and crappy x87 FPU to produce correct values.
# Would be nice if Clang had something comparable.
ifeq ($(YQ2_ARCH), i386)
ifeq ($(COMPILER), gcc)
CFLAGS += -ffloat-store
endif
endif

# Force SSE math on x86_64. All sane compilers should do this
# anyway, just to protect us from broken Linux distros.
ifeq ($(YQ2_ARCH), x86_64)
CFLAGS += -mfpmath=sse
endif

# ----------

# Systemwide installation.
ifeq ($(WITH_SYSTEMWIDE),yes)
CFLAGS += -DSYSTEMWIDE
ifneq ($(WITH_SYSTEMDIR),"")
CFLAGS += -DSYSTEMDIR=\"$(WITH_SYSTEMDIR)\"
endif
endif

# ----------

# Just set IOAPI_NO_64 on everything that's not Linux or Windows,
# otherwise minizip will use fopen64(), fseek64() and friends that
# may be unavailable. This is - of course - not really correct, in
# a better world we would set -DIOAPI_NO_64 to force everything to
# fopen(), fseek() and so on and -D_FILE_OFFSET_BITS=64 to let the
# libc headers do their work. Currently we can't do that because
# Quake II uses nearly everywere int instead of off_t...
#
# This may have the side effect that ZIP files larger than 2GB are
# unsupported. But I doubt that anyone has such large files, they
# would likely hit other internal limits.
ifneq ($(YQ2_OSTYPE),Windows)
ifneq ($(YQ2_OSTYPE),Linux)
ZIPCFLAGS += -DIOAPI_NO_64
endif
endif

# We don't support encrypted ZIP files.
ZIPCFLAGS += -DNOUNCRYPT

# ----------

# Extra CFLAGS for SDL.
SDLCFLAGS := $(shell sdl2-config --cflags)

# ----------

# Base include path.
ifeq ($(YQ2_OSTYPE),Linux)
INCLUDE := -I/usr/include
else ifeq ($(YQ2_OSTYPE),FreeBSD)
INCLUDE := -I/usr/local/include
else ifeq ($(YQ2_OSTYPE),OpenBSD)
INCLUDE := -I/usr/local/include
else ifeq ($(YQ2_OSTYPE),Windows)
INCLUDE := -I/usr/include
endif

# ----------

# Base LDFLAGS.
ifeq ($(YQ2_OSTYPE),Linux)
LDFLAGS := -L/usr/lib -lm -ldl -rdynamic
else ifeq ($(YQ2_OSTYPE),FreeBSD)
LDFLAGS := -L/usr/local/lib -lm
else ifeq ($(YQ2_OSTYPE),OpenBSD)
LDFLAGS := -L/usr/local/lib -lm
else ifeq ($(YQ2_OSTYPE),Windows)
LDFLAGS := -L/usr/lib -lws2_32 -lwinmm -static-libgcc
endif

# Keep symbols hidden.
CFLAGS += -fvisibility=hidden
LDFLAGS += -fvisibility=hidden

ifneq ($(YQ2_OSTYPE), OpenBSD)
# for some reason the OpenBSD linker doesn't support this...
LDFLAGS += -Wl,--no-undefined
endif

# ----------

# Extra LDFLAGS for SDL
SDLLDFLAGS := $(shell sdl2-config --libs)

# The renderer libs don't need libSDL2main, libmingw32 or -mwindows.
ifeq ($(YQ2_OSTYPE), Windows)
DLL_SDLLDFLAGS = $(subst -mwindows,,$(subst -lmingw32,,$(subst -lSDL2main,,$(SDLLDFLAGS))))
endif

# ----------

# When make is invoked by "make VERBOSE=1" print
# the compiler and linker commands.
ifdef VERBOSE
Q :=
else
Q := @
endif

# ----------

# Phony targets
.PHONY : all client game icon server ref_gl ref_soft

# ----------

# Builds everything
all: config client server game ref_gl ref_soft

# ----------

# Print config values
config:
	@echo "Build configuration"
	@echo "============================"
	@echo "WITH_OPENAL = $(WITH_OPENAL)"
	@echo "WITH_SYSTEMWIDE = $(WITH_SYSTEMWIDE)"
	@echo "WITH_SYSTEMDIR = $(WITH_SYSTEMDIR)"
	@echo "============================"
	@echo ""

# ----------

# Special target to compile the icon on Windows
ifeq ($(YQ2_OSTYPE), Windows)
icon:
	@echo "===> WR build/icon/icon.res"
	${Q}mkdir -p build/icon
	${Q}windres src/backends/windows/icon.rc -O COFF -o build/icon/icon.res
endif

# ----------

# Cleanup
clean:
	@echo "===> CLEAN"
	${Q}rm -Rf build bin/*

cleanall:
	@echo "===> CLEAN"
	${Q}rm -Rf build bin

# ----------

# The client
ifeq ($(YQ2_OSTYPE), Windows)
client:
	@echo "===> Building yquake2.exe"
	${Q}mkdir -p bin
	$(MAKE) bin/yquake2.exe

build/client/%.o: %.c
	@echo "===> CC $<"
	${Q}mkdir -p $(@D)
	${Q}$(CC) -c $(CFLAGS) $(SDLCFLAGS) $(ZIPCFLAGS) $(INCLUDE) -o $@ $<

bin/yquake2.exe : LDFLAGS += -mwindows

ifeq ($(WITH_OPENAL),yes)
bin/yquake2.exe : CFLAGS += -DUSE_OPENAL -DDEFAULT_OPENAL_DRIVER='"openal32.dll"'
endif

else # not Windows

client:
	@echo "===> Building quake2"
	${Q}mkdir -p bin
	$(MAKE) bin/quake2

build/client/%.o: %.c
	@echo "===> CC $<"
	${Q}mkdir -p $(@D)
	${Q}$(CC) -c $(CFLAGS) $(SDLCFLAGS) $(ZIPCFLAGS) $(INCLUDE) -o $@ $<

bin/quake2 : CFLAGS += -Wno-unused-result

ifeq ($(WITH_OPENAL),yes)
ifeq ($(YQ2_OSTYPE), OpenBSD)
bin/quake2 : CFLAGS += -DUSE_OPENAL -DDEFAULT_OPENAL_DRIVER='"libopenal.so"'
else
bin/quake2 : CFLAGS += -DUSE_OPENAL -DDEFAULT_OPENAL_DRIVER='"libopenal.so.1"'
endif
endif

ifeq ($(YQ2_OSTYPE), FreeBSD)
bin/quake2 : LDFLAGS += -lexecinfo
endif

ifeq ($(YQ2_OSTYPE), FreeBSD)
bin/quake2 : LDFLAGS += -Wl,-z,origin,-rpath='$$ORIGIN/lib' -lexecinfo
else ifeq ($(YQ2_OSTYPE), Linux)
bin/quake2 : LDFLAGS += -Wl,-z,origin,-rpath='$$ORIGIN/lib'
endif

ifeq ($(WITH_SYSTEMWIDE),yes)
ifneq ($(WITH_SYSTEMDIR),"")
ifeq ($(YQ2_OSTYPE), FreeBSD)
bin/quake2 : LDFLAGS += -Wl,-z,origin,-rpath='$(WITH_SYSTEMDIR)/lib'
else ifeq ($(YQ2_OSTYPE), Linux)
bin/quake2 : LDFLAGS += -Wl,-z,origin,-rpath='$(WITH_SYSTEMDIR)/lib'
endif
else
ifeq ($(YQ2_OSTYPE), FreeBSD)
bin/quake2 : LDFLAGS += -Wl,-z,origin,-rpath='/usr/share/games/quake2/lib'
else ifeq ($(YQ2_OSTYPE), Linux)
bin/quake2 : LDFLAGS += -Wl,-z,origin,-rpath='/usr/share/games/quake2/lib'
endif
endif
endif
endif

# ----------

# The server
ifeq ($(YQ2_OSTYPE), Windows)
server:
	@echo "===> Building q2ded"
	${Q}mkdir -p bin
	$(MAKE) bin/q2ded.exe

build/server/%.o: %.c
	@echo "===> CC $<"
	${Q}mkdir -p $(@D)
	${Q}$(CC) -c $(CFLAGS) $(ZIPCFLAGS) $(INCLUDE) -o $@ $<

bin/q2ded.exe : CFLAGS += -DDEDICATED_ONLY

else # not Windows

server:
	@echo "===> Building q2ded"
	${Q}mkdir -p bin
	$(MAKE) bin/q2ded

build/server/%.o: %.c
	@echo "===> CC $<"
	${Q}mkdir -p $(@D)
	${Q}$(CC) -c $(CFLAGS) $(ZIPCFLAGS) $(INCLUDE) -o $@ $<

bin/q2ded : CFLAGS += -DDEDICATED_ONLY -Wno-unused-result

ifeq ($(YQ2_OSTYPE), FreeBSD)
bin/q2ded : LDFLAGS += -lexecinfo
endif
endif

# ----------

# The OpenGL renderer lib

ifeq ($(YQ2_OSTYPE), Windows)

ref_gl:
	@echo "===> Building ref_gl.dll"
	$(MAKE) bin/ref_gl.dll

bin/ref_gl.dll : LDFLAGS += -lopengl32 -shared

else # not Windows

ref_gl:
	@echo "===> Building ref_gl.so"
	$(MAKE) bin/ref_gl.so


bin/ref_gl.so : CFLAGS += -fPIC
bin/ref_gl.so : LDFLAGS += -shared -lGL

endif # OS specific ref_gl stuff

build/ref_gl/%.o: %.c
	@echo "===> CC $<"
	${Q}mkdir -p $(@D)
	${Q}$(CC) -c $(CFLAGS) $(SDLCFLAGS) $(INCLUDE) -o $@ $<

# ----------

# The soft renderer lib

ifeq ($(YQ2_OSTYPE), Windows)

ref_soft:
	@echo "===> Building ref_soft.dll"
	$(MAKE) bin/ref_soft.dll

bin/ref_soft.dll : LDFLAGS += -shared

else # not Windows

ref_soft:
	@echo "===> Building ref_soft.so"
	$(MAKE) bin/ref_soft.so

bin/ref_soft.so : CFLAGS += -fPIC
bin/ref_soft.so : LDFLAGS += -shared

endif # OS specific ref_soft stuff

build/ref_soft/%.o: %.c
	@echo "===> CC $<"
	${Q}mkdir -p $(@D)
	${Q}$(CC) -c $(CFLAGS) $(SDLCFLAGS) $(INCLUDE) $(GLAD_INCLUDE) -o $@ $<

# ----------

# The baseq2 game
ifeq ($(YQ2_OSTYPE), Windows)
game:
	@echo "===> Building baseq2/game.dll"
	${Q}mkdir -p bin/baseq2
	$(MAKE) bin/baseq2/game.dll

build/baseq2/%.o: %.c
	@echo "===> CC $<"
	${Q}mkdir -p $(@D)
	${Q}$(CC) -c $(CFLAGS) $(INCLUDE) -o $@ $<

bin/baseq2/game.dll : LDFLAGS += -shared

else # not Windows

game:
	@echo "===> Building baseq2/game.so"
	${Q}mkdir -p bin/baseq2
	$(MAKE) bin/baseq2/game.so

build/baseq2/%.o: %.c
	@echo "===> CC $<"
	${Q}mkdir -p $(@D)
	${Q}$(CC) -c $(CFLAGS) $(INCLUDE) -o $@ $<

bin/baseq2/game.so : CFLAGS += -fPIC -Wno-unused-result
bin/baseq2/game.so : LDFLAGS += -shared
endif

# ----------

# Used by the game
GAME_OBJS_ = \
	src/common/shared/flash.o \
	src/common/shared/rand.o \
	src/common/shared/shared.o \
	src/game/g_ai.o \
	src/game/g_chase.o \
	src/game/g_cmds.o \
	src/game/g_combat.o \
	src/game/g_func.o \
	src/game/g_items.o \
	src/game/g_main.o \
	src/game/g_misc.o \
	src/game/g_monster.o \
	src/game/g_phys.o \
	src/game/g_spawn.o \
	src/game/g_svcmds.o \
	src/game/g_target.o \
	src/game/g_trigger.o \
	src/game/g_turret.o \
	src/game/g_utils.o \
	src/game/g_weapon.o \
	src/game/monster/berserker/berserker.o \
	src/game/monster/boss2/boss2.o \
	src/game/monster/boss3/boss3.o \
	src/game/monster/boss3/boss31.o \
	src/game/monster/boss3/boss32.o \
	src/game/monster/brain/brain.o \
	src/game/monster/chick/chick.o \
	src/game/monster/flipper/flipper.o \
	src/game/monster/float/float.o \
	src/game/monster/flyer/flyer.o \
	src/game/monster/gladiator/gladiator.o \
	src/game/monster/gunner/gunner.o \
	src/game/monster/hover/hover.o \
	src/game/monster/infantry/infantry.o \
	src/game/monster/insane/insane.o \
	src/game/monster/medic/medic.o \
	src/game/monster/misc/move.o \
	src/game/monster/mutant/mutant.o \
	src/game/monster/parasite/parasite.o \
	src/game/monster/soldier/soldier.o \
	src/game/monster/supertank/supertank.o \
	src/game/monster/tank/tank.o \
	src/game/player/client.o \
	src/game/player/hud.o \
	src/game/player/trail.o \
	src/game/player/view.o \
	src/game/player/weapon.o \
	src/game/savegame/savegame.o

# ----------

# Used by the client
CLIENT_OBJS_ := \
	src/backends/generic/misc.o \
	src/client/cl_cin.o \
	src/client/cl_console.o \
	src/client/cl_download.o \
	src/client/cl_effects.o \
	src/client/cl_entities.o \
	src/client/cl_input.o \
	src/client/cl_inventory.o \
	src/client/cl_keyboard.o \
	src/client/cl_lights.o \
	src/client/cl_main.o \
	src/client/cl_network.o \
	src/client/cl_parse.o \
	src/client/cl_particles.o \
	src/client/cl_prediction.o \
	src/client/cl_screen.o \
	src/client/cl_tempentities.o \
	src/client/cl_view.o \
	src/client/input/sdl.o \
	src/client/menu/menu.o \
	src/client/menu/qmenu.o \
	src/client/menu/videomenu.o \
	src/client/sound/sdl.o \
	src/client/sound/ogg.o \
	src/client/sound/openal.o \
	src/client/sound/qal.o \
	src/client/sound/sound.o \
	src/client/sound/wave.o \
	src/client/vid/glimp_sdl.o \
	src/client/vid/vid.o \
	src/common/argproc.o \
	src/common/clientserver.o \
	src/common/collision.o \
	src/common/crc.o \
	src/common/cmdparser.o \
	src/common/cvar.o \
	src/common/filesystem.o \
	src/common/glob.o \
	src/common/md4.o \
	src/common/movemsg.o \
	src/common/frame.o \
	src/common/netchan.o \
	src/common/pmove.o \
	src/common/szone.o \
	src/common/zone.o \
	src/common/shared/flash.o \
	src/common/shared/rand.o \
	src/common/shared/shared.o \
	src/common/unzip/ioapi.o \
	src/common/unzip/miniz.o \
	src/common/unzip/unzip.o \
	src/server/sv_cmd.o \
	src/server/sv_conless.o \
	src/server/sv_entities.o \
	src/server/sv_game.o \
	src/server/sv_init.o \
	src/server/sv_main.o \
	src/server/sv_save.o \
	src/server/sv_send.o \
	src/server/sv_user.o \
	src/server/sv_world.o

ifeq ($(YQ2_OSTYPE), Windows)
CLIENT_OBJS_ += \
	src/backends/windows/main.o \
	src/backends/windows/network.o \
	src/backends/windows/system.o \
	src/backends/windows/shared/hunk.o
else
CLIENT_OBJS_ += \
	src/backends/unix/main.o \
	src/backends/unix/network.o \
	src/backends/unix/signalhandler.o \
	src/backends/unix/system.o \
	src/backends/unix/shared/hunk.o
endif

# ----------

REFGL_OBJS_ := \
	src/client/refresh/gl/qgl.o \
	src/client/refresh/gl/gl_draw.o \
	src/client/refresh/gl/gl_image.o \
	src/client/refresh/gl/gl_light.o \
	src/client/refresh/gl/gl_lightmap.o \
	src/client/refresh/gl/gl_main.o \
	src/client/refresh/gl/gl_mesh.o \
	src/client/refresh/gl/gl_misc.o \
	src/client/refresh/gl/gl_model.o \
	src/client/refresh/gl/gl_scrap.o \
	src/client/refresh/gl/gl_surf.o \
	src/client/refresh/gl/gl_warp.o \
	src/client/refresh/gl/gl_sdl.o \
	src/client/refresh/gl/gl_md2.o \
	src/client/refresh/gl/gl_sp2.o \
	src/client/refresh/files/pcx.o \
	src/client/refresh/files/stb.o \
	src/client/refresh/files/wal.o \
	src/client/refresh/files/pvs.o \
	src/common/shared/shared.o \
	src/common/md4.o

ifeq ($(YQ2_OSTYPE), Windows)
REFGL_OBJS_ += \
	src/backends/windows/shared/hunk.o
else # not Windows
REFGL_OBJS_ += \
	src/backends/unix/shared/hunk.o
endif

# ----------

REFSOFT_OBJS_ := \
	src/client/refresh/soft/sw_aclip.o \
	src/client/refresh/soft/sw_alias.o \
	src/client/refresh/soft/sw_bsp.o \
	src/client/refresh/soft/sw_draw.o \
	src/client/refresh/soft/sw_edge.o \
	src/client/refresh/soft/sw_image.o \
	src/client/refresh/soft/sw_light.o \
	src/client/refresh/soft/sw_main.o \
	src/client/refresh/soft/sw_misc.o \
	src/client/refresh/soft/sw_model.o \
	src/client/refresh/soft/sw_part.o \
	src/client/refresh/soft/sw_poly.o \
	src/client/refresh/soft/sw_polyset.o \
	src/client/refresh/soft/sw_rast.o \
	src/client/refresh/soft/sw_scan.o \
	src/client/refresh/soft/sw_sprite.o \
	src/client/refresh/soft/sw_surf.o \
	src/client/refresh/files/pcx.o \
	src/client/refresh/files/stb.o \
	src/client/refresh/files/wal.o \
	src/client/refresh/files/pvs.o \
	src/common/shared/shared.o \
	src/common/md4.o

ifeq ($(YQ2_OSTYPE), Windows)
REFSOFT_OBJS_ += \
	src/backends/windows/shared/hunk.o
else # not Windows
REFSOFT_OBJS_ += \
	src/backends/unix/shared/hunk.o
endif

# ----------

# Used by the server
SERVER_OBJS_ := \
	src/backends/generic/misc.o \
	src/common/argproc.o \
	src/common/clientserver.o \
	src/common/collision.o \
	src/common/crc.o \
	src/common/cmdparser.o \
	src/common/cvar.o \
	src/common/filesystem.o \
	src/common/glob.o \
	src/common/md4.o \
	src/common/frame.o \
	src/common/movemsg.o \
	src/common/netchan.o \
	src/common/pmove.o \
	src/common/szone.o \
	src/common/zone.o \
	src/common/shared/rand.o \
	src/common/shared/shared.o \
	src/common/unzip/ioapi.o \
	src/common/unzip/miniz.o \
	src/common/unzip/unzip.o \
	src/server/sv_cmd.o \
	src/server/sv_conless.o \
	src/server/sv_entities.o \
	src/server/sv_game.o \
	src/server/sv_init.o \
	src/server/sv_main.o \
	src/server/sv_save.o \
	src/server/sv_send.o \
	src/server/sv_user.o \
	src/server/sv_world.o

ifeq ($(YQ2_OSTYPE), Windows)
SERVER_OBJS_ += \
	src/backends/windows/main.o \
	src/backends/windows/network.o \
	src/backends/windows/system.o \
	src/backends/windows/shared/hunk.o
else # not Windows
SERVER_OBJS_ += \
	src/backends/unix/main.o \
	src/backends/unix/network.o \
	src/backends/unix/signalhandler.o \
	src/backends/unix/system.o \
	src/backends/unix/shared/hunk.o
endif

# ----------

# Rewrite pathes to our object directory.
CLIENT_OBJS = $(patsubst %,build/client/%,$(CLIENT_OBJS_))
REFGL_OBJS = $(patsubst %,build/ref_gl/%,$(REFGL_OBJS_))
REFSOFT_OBJS = $(patsubst %,build/ref_soft/%,$(REFSOFT_OBJS_))
SERVER_OBJS = $(patsubst %,build/server/%,$(SERVER_OBJS_))
GAME_OBJS = $(patsubst %,build/baseq2/%,$(GAME_OBJS_))

# ----------

# Generate header dependencies.
CLIENT_DEPS= $(CLIENT_OBJS:.o=.d)
REFGL_DEPS= $(REFGL_OBJS:.o=.d)
REFSOFT_DEPS= $(REFSOFT_OBJS:.o=.d)
SERVER_DEPS= $(SERVER_OBJS:.o=.d)
GAME_DEPS= $(GAME_OBJS:.o=.d)

# Suck header dependencies in.
-include $(CLIENT_DEPS)
-include $(REFGL_DEPS)
-include $(SERVER_DEPS)
-include $(GAME_DEPS)

# ----------

# bin/quake2
ifeq ($(YQ2_OSTYPE), Windows)
bin/yquake2.exe : $(CLIENT_OBJS) icon
	@echo "===> LD $@"
	${Q}$(CC) build/icon/icon.res $(CLIENT_OBJS) $(LDFLAGS) $(SDLLDFLAGS) -o $@
	$(Q)strip $@
else
bin/quake2 : $(CLIENT_OBJS)
	@echo "===> LD $@"
	${Q}$(CC) $(CLIENT_OBJS) $(LDFLAGS) $(SDLLDFLAGS) -o $@
endif

# bin/q2ded
ifeq ($(YQ2_OSTYPE), Windows)
bin/q2ded.exe : $(SERVER_OBJS) icon
	@echo "===> LD $@.exe"
	${Q}$(CC) build/icon/icon.res $(SERVER_OBJS) $(LDFLAGS) $(SDLLDFLAGS) -o $@
	$(Q)strip $@
else
bin/q2ded : $(SERVER_OBJS)
	@echo "===> LD $@"
	${Q}$(CC) $(SERVER_OBJS) $(LDFLAGS) -o $@
endif

# bin/ref_gl.so
ifeq ($(YQ2_OSTYPE), Windows)
bin/ref_gl.dll : $(REFGL_OBJS)
	@echo "===> LD $@"
	${Q}$(CC) $(REFGL_OBJS) $(LDFLAGS) $(DLL_SDLLDFLAGS) -o $@
	$(Q)strip $@
else
bin/ref_gl.so : $(REFGL_OBJS)
	@echo "===> LD $@"
	${Q}$(CC) $(REFGL_OBJS) $(LDFLAGS) $(SDLLDFLAGS) -o $@
endif

# bin/ref_soft.so
ifeq ($(YQ2_OSTYPE), Windows)
bin/ref_soft.dll : $(REFSOFT_OBJS)
	@echo "===> LD $@"
	${Q}$(CC) $(REFSOFT_OBJS) $(LDFLAGS) $(DLL_SDLLDFLAGS) -o $@
	$(Q)strip $@
else
bin/ref_soft.so : $(REFSOFT_OBJS)
	@echo "===> LD $@"
	${Q}$(CC) $(REFSOFT_OBJS) $(LDFLAGS) $(SDLLDFLAGS) -o $@
endif

# bin/baseq2/game.so
ifeq ($(YQ2_OSTYPE), Windows)
bin/baseq2/game.dll : $(GAME_OBJS)
	@echo "===> LD $@"
	${Q}$(CC) $(GAME_OBJS) $(LDFLAGS) -o $@
	$(Q)strip $@
else
bin/baseq2/game.so : $(GAME_OBJS)
	@echo "===> LD $@"
	${Q}$(CC) $(GAME_OBJS) $(LDFLAGS) -o $@
endif

# ----------
