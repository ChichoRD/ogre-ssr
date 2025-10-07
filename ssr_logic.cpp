#include "ssr_logic.hpp"
#include <OgreMaterial.h>
#include <OgreTechnique.h>
#include <OgreCompositorChain.h>

#include <iostream>

const std::string ssr_logic::name = "ssr";

struct ssr_instance : public Ogre::CompositorInstance::Listener {
    std::reference_wrapper<Ogre::Viewport> viewport;
    uint16_t target_width;
    uint16_t target_height;

    static constexpr std::string_view raytrace_material_name = "ssr/output_raytrace";

    ssr_instance(Ogre::Viewport &viewport) : viewport{viewport}, target_width{0}, target_height{0} { }

    void notify_viewport_size(uint16_t width, uint16_t height) {
        target_width = width;
        target_height = height;
    }

    void notifyMaterialSetup(Ogre::uint32 pass_id, Ogre::MaterialPtr &mat) override {
        (void)pass_id;
        if (mat->getName().ends_with(raytrace_material_name)) {
            auto fragment_parameters =
                mat->getTechnique(0)->getPass(0)->getFragmentProgramParameters();
            const auto &camera = *viewport.get().getCamera();

            fragment_parameters->setNamedConstant(
                "raytrace_projection_matrix",
                camera.getProjectionMatrix()
            );
            fragment_parameters->setNamedConstant(
                "raytrace_i_projection_matrix",
                camera.getProjectionMatrix().inverse()
            );
            fragment_parameters->setNamedConstant(
                "raytrace_i_view_matrix",
                camera.getViewMatrix().inverse()
            );
        }
    }
    void notifyMaterialRender(Ogre::uint32 pass_id, Ogre::MaterialPtr &mat) override {
        (void)pass_id;
        if (mat->getName().ends_with(raytrace_material_name)) {
            auto fragment_parameters =
                mat->getTechnique(0)->getPass(0)->getFragmentProgramParameters();
            const auto &camera = *viewport.get().getCamera();

            fragment_parameters->setNamedConstant(
                "raytrace_projection_matrix",
                camera.getProjectionMatrix()
            );
            fragment_parameters->setNamedConstant(
                "raytrace_i_projection_matrix",
                camera.getProjectionMatrix().inverse()
            );
            fragment_parameters->setNamedConstant(
                "raytrace_i_view_matrix",
                camera.getViewMatrix().inverse()
            );
        }
    }
};

Ogre::CompositorInstance::Listener *ssr_logic::createListener(Ogre::CompositorInstance *instance) {
    Ogre::Viewport &viewport = *instance->getChain()->getViewport();
    ssr_instance* ssr = new ssr_instance{viewport};
    ssr->notify_viewport_size(viewport.getActualWidth(), viewport.getActualHeight());
    return ssr;
}
