# Builds snippets.json for the gallery's "Copy QML" button, from the example in
# each control's header comment, so the snippets cannot drift from the
# controls. Run by gallery/CMakeLists.txt as
#   cmake -DUI_DIR=<ui> -DDEMOS_DIR=<demos> -DOUT=<file> -P snippets.cmake
#
# The example is the first run of lines that begin with "//   " (two slashes
# and at least three spaces) in the comment above the type, dedented. A type
# without one gets "Type {}". JSON shape: {"demos": [names], "snippets": {name: text}}.

file(GLOB demo_files RELATIVE "${DEMOS_DIR}" "${DEMOS_DIR}/*Demo.qml")
list(SORT demo_files)

# CMake lists split on ";" and treat [ ] specially: hide them in the text.
function(protect text out)
    string(REPLACE ";" "<SEMI>" text "${text}")
    string(REPLACE "[" "<LB>" text "${text}")
    string(REPLACE "]" "<RB>" text "${text}")
    set(${out} "${text}" PARENT_SCOPE)
endfunction()

function(json_escape text out)
    string(REPLACE "\\" "\\\\" text "${text}")
    string(REPLACE "\"" "\\\"" text "${text}")
    string(REPLACE "\t" "\\t" text "${text}")
    string(REPLACE "\n" "\\n" text "${text}")
    set(${out} "${text}" PARENT_SCOPE)
endfunction()

set(names "")
set(entries "")
foreach(demo IN LISTS demo_files)
    string(REGEX REPLACE "Demo\\.qml$" "" type "${demo}")
    list(APPEND names "\"${type}\"")
    set(snippet "${type} {}")
    set(file "${UI_DIR}/${type}.qml")
    if(EXISTS "${file}")
        file(READ "${file}" content)
        protect("${content}" content)
        string(REPLACE "\n" ";" lines "${content}")
        set(found FALSE)
        set(block "")
        set(min_indent 1000)
        foreach(line IN LISTS lines)
            if(line MATCHES "^//   ( *)(.*)$")
                string(LENGTH "${CMAKE_MATCH_1}" extra)
                math(EXPR indent "${extra}")
                if(indent LESS min_indent)
                    set(min_indent ${indent})
                endif()
                # Keep the indent beyond the 3 spaces and the text.
                list(APPEND block "${CMAKE_MATCH_1}${CMAKE_MATCH_2}")
                set(found TRUE)
            elseif(found)
                break()
            elseif(NOT line MATCHES "^//" AND NOT line MATCHES "^import" AND NOT line STREQUAL "")
                break() # past the header comment
            endif()
        endforeach()
        if(found)
            set(snippet "")
            foreach(line IN LISTS block)
                string(SUBSTRING "${line}" ${min_indent} -1 line)
                string(APPEND snippet "${line}\n")
            endforeach()
            string(REGEX REPLACE "\n$" "" snippet "${snippet}")
        endif()
    endif()
    json_escape("${snippet}" escaped)
    list(APPEND entries "    \"${type}\": \"${escaped}\"")
endforeach()

list(JOIN names ", " names_json)
list(JOIN entries ",\n" entries_json)
string(REPLACE "<SEMI>" ";" entries_json "${entries_json}")
string(REPLACE "<LB>" "[" entries_json "${entries_json}")
string(REPLACE "<RB>" "]" entries_json "${entries_json}")
file(WRITE "${OUT}.tmp" "{\n  \"demos\": [${names_json}],\n  \"snippets\": {\n${entries_json}\n  }\n}\n")
file(RENAME "${OUT}.tmp" "${OUT}")
