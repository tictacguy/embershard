cmake_minimum_required(VERSION 3.20)
project(embershard C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# --- Metal-first: macOS backend primario ---
if(APPLE)
    # Metal-first: primary GPU backend on Apple Silicon
    set(GGML_METAL ON CACHE BOOL "Enable Metal backend" FORCE)
    set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "Embed Metal shaders" FORCE)
endif()

set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)

add_subdirectory(vendor/llama.cpp)

# --- Embershard static library (Swift app links against this) ---
set(ES_ENGINE_SOURCES
    src/es_engine.c
    src/es_bench.c
    src/es_kvcache.c
    src/es_agent.c
    src/es_orchestrator.c
    src/es_memory.c
    src/es_api.c
)

add_library(embershard_engine STATIC ${ES_ENGINE_SOURCES})
target_include_directories(embershard_engine PUBLIC
    include
    vendor/llama.cpp/include
    vendor/llama.cpp/ggml/include
)
target_link_libraries(embershard_engine PUBLIC llama ggml)
target_compile_options(embershard_engine PRIVATE -Wall -Wextra -O2)

# --- CLI executable ---
add_executable(embershard
    src/main.c
    ${ES_ENGINE_SOURCES}
)

target_include_directories(embershard PRIVATE
    include
    vendor/llama.cpp/include
    vendor/llama.cpp/ggml/include
)

target_link_libraries(embershard PRIVATE llama ggml)

if(APPLE)
    target_link_libraries(embershard PRIVATE "-framework Foundation" "-framework Metal" "-framework MetalKit")
endif()

target_compile_options(embershard PRIVATE -Wall -Wextra -O2)

# --- Test executable ---
add_executable(test_engine
    src/test_engine.c
    ${ES_ENGINE_SOURCES}
)

target_include_directories(test_engine PRIVATE
    include
    vendor/llama.cpp/include
    vendor/llama.cpp/ggml/include
)

target_link_libraries(test_engine PRIVATE llama ggml)

if(APPLE)
    target_link_libraries(test_engine PRIVATE "-framework Foundation" "-framework Metal" "-framework MetalKit")
endif()

target_compile_options(test_engine PRIVATE -Wall -Wextra -O2)
