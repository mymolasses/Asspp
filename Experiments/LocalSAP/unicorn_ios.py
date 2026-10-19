"""Fix the pinned fork's host-CPU probe when cross-compiling on Intel macOS."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
marker = 'ASSPP_QEMU_CPU'
if marker not in source:
    anchor = '    execute_process(COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/qemu/configure\n'
    assert source.count(anchor) == 1, 'Pinned Unicorn CMake layout changed'
    source = source.replace(anchor, '''    set(ASSPP_QEMU_CPU "")
    if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
        set(ASSPP_QEMU_CPU "--cpu=aarch64")
    endif()
''' + anchor + '        ${ASSPP_QEMU_CPU}\n')
    path.write_text(source)
