#include <OgreMaterialManager.h>
#include <OgreCompositor.h>
#include "ssr_logic.hpp"

struct ssr_compositor : public Ogre::MaterialManager::Listener {
    static constexpr size_t pipelines_count = 1;
    
    // ssr_logic ssr{};
    
    Ogre::TexturePtr normal_depth_rough{};
    Ogre::TexturePtr scene{};
    Ogre::TexturePtr temp{};
    std::array<Ogre::CompositorPtr, pipelines_count> pipelines{};

    Ogre::Technique *handleSchemeNotFound(
        unsigned short schemeIndex, 
        const Ogre::String& schemeName,
        Ogre::Material* originalMaterial,
        unsigned short lodIndex, 
        const Ogre::Renderable* rend
    ) override;


    void init(Ogre::CompositorManager &composer, Ogre::Viewport &viewport);
    void deinit(Ogre::CompositorManager &composer, Ogre::TextureManager &texture_manager);

    void enable_pipelines(Ogre::CompositorManager &composer, Ogre::Viewport &viewport);
    void disable_pipelines(Ogre::CompositorManager &composer, Ogre::Viewport &viewport);
};