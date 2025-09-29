#include "ssr_logic.hpp"
#include <OgreMaterial.h>
#include <OgreTechnique.h>
#include <OgreCompositorChain.h>

const std::string ssr_logic::name = "ssr";

struct ssr_instance : public Ogre::CompositorInstance::Listener {
    uint16_t target_width;
    uint16_t target_height;

    float step_size;
    float vignette_radius;
    float vignette_feather;

    void notify_viewport_size(uint16_t width, uint16_t height) {
        target_width = width;
        target_height = height;
    }

    void notifyMaterialSetup(Ogre::uint32 pass_id, Ogre::MaterialPtr &mat) override {
        static constexpr uint32_t pass_id_ssr_normal_depth = 0;
        static constexpr uint32_t pass_id_ssr_raytrace = 1;
        
        switch (pass_id) {
        case pass_id_ssr_normal_depth: {

            break;
        }
        case pass_id_ssr_raytrace: {
            mat->load();
            Ogre::GpuProgramParametersSharedPtr fparams =
                mat->getTechnique(0)->getPass(0)->getFragmentProgramParameters();

            fparams->setNamedConstant("step_size", step_size);
            fparams->setNamedConstant("vignette_radius", vignette_radius);
            fparams->setNamedConstant("vignette_feather", vignette_feather);
            break;
        }
        }
    }
    void notifyMaterialRender(Ogre::uint32 pass_id, Ogre::MaterialPtr &mat) override {
        (void)pass_id;
        (void)mat;
    }
};

Ogre::CompositorInstance::Listener *ssr_logic::createListener(Ogre::CompositorInstance *instance) {
    ssr_instance* ssr = new ssr_instance;
    Ogre::Viewport* viewport = instance->getChain()->getViewport();
    ssr->notify_viewport_size(viewport->getActualWidth(), viewport->getActualHeight());
    return ssr;
}
