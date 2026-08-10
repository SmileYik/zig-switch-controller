set(DEPS nvs_flash)
if(CONFIG_ESP_WIFI_ENABLED)
    list(APPEND DEPS esp_wifi esp_netif esp_event)
endif()
if(CONFIG_BT_ENABLED)
    list(APPEND DEPS bt)
endif()

set(MAIN_SRCS "placeholder.c")

idf_component_register(
    SRCS ${MAIN_SRCS}
    INCLUDE_DIRS "." "${CMAKE_SOURCE_DIR}/include"
    REQUIRES ${DEPS}
)

# Build your project or examples

set(ZIG_EXAMPLE_ARG "") # default is main/app.zig

include(${CMAKE_SOURCE_DIR}/cmake/zig-config.cmake)

# FIXME: need add <cmath> for build kalman
if(TARGET __idf_espressif__esp-dsp AND IDF_VERSION_MAJOR EQUAL 6)
    target_compile_options(__idf_espressif__esp-dsp PRIVATE
        $<$<COMPILE_LANGUAGE:CXX>:-includecmath>
    )
endif()

