cmake_minimum_required(VERSION 3.30)


project(ogre0 CXX)
    add_executable(
        ${PROJECT_NAME}
        main.cpp
        SinbadExample.cpp
        ssr_logic.cpp
        ssr_compositor.cpp
    )
    target_compile_options(
        ${PROJECT_NAME}
        PRIVATE
        -Wall
        -Wextra
        -Wpedantic
        -Werror
    )   

    target_include_directories(
        ${PROJECT_NAME}
        SYSTEM
        PUBLIC
        C:/Users/chich/Projects/source/ogre/build/debug-x64/sdk/include/Ogre
        C:/Users/chich/Projects/source/ogre/build/debug-x64/sdk/include/Ogre/Bites
        C:/Users/chich/Projects/source/ogre/build/debug-x64/sdk/include/Ogre/RTShaderSystem
        C:/Users/chich/Projects/source/ogre/build/debug-x64/sdk/include/Ogre/Overlay
        C:/Users/chich/Projects/source/ogre/build/debug-x64/Dependencies/include/SDL2
    )

    target_link_directories(
        ${PROJECT_NAME}
        PUBLIC
        C:/Users/chich/Projects/source/ogre/build/debug-x64/lib/Debug
    )

    target_link_libraries(
        ${PROJECT_NAME}
        PUBLIC
        OgreMain_d
        OgreBites_d
        OgreRTShaderSystem_d
        OgreOverlay_d
    )