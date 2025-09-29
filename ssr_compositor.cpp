#include "ssr_compositor.hpp"
#include <OgreCompositorManager.h>
#include <OgreTextureManager.h>
#include <OgreViewport.h>
#include <OgreMaterial.h>
#include <OgreTechnique.h>
#include <OgreCompositor.h>
#include <OgreCompositionTargetPass.h>
#include <OgreShaderGenerator.h>

#include <array>
#include <string_view>

static const std::string texture_group_name = "General";

static const std::string rt_out_ndr_name = "ssr_normal_depth_rough";
static const std::string rt_in_scene_name = "ssr_scene";
static const std::string rt_in_out_temp_name = "ssr_temp";

static const std::string material_ndr_name = "ssr/output_normal_depth_rough";
static const std::string material_raytrace_name = "ssr/output_raytrace";
static const std::string material_copyback_name = "Ogre/Compositor/Copyback";

static const std::string scheme_ndr_name = "ssr_output_normal_depth_rough_scheme";


static auto ssr_compositor_init_textures(
    Ogre::TextureManager &texture_manager,
    Ogre::Viewport &viewport
) {
    Ogre::TexturePtr normal_depth_rough = texture_manager.createManual(
        rt_out_ndr_name,
        texture_group_name,
        Ogre::TEX_TYPE_2D,
        viewport.getActualWidth(),
        viewport.getActualHeight(),
        0,
        Ogre::PF_FLOAT32_RGBA,
        Ogre::TU_RENDERTARGET | Ogre::TU_STATIC_WRITE_ONLY
    );

    Ogre::TexturePtr temp = texture_manager.createManual(
        rt_in_out_temp_name,
        texture_group_name,
        Ogre::TEX_TYPE_2D,
        viewport.getActualWidth(),
        viewport.getActualHeight(),
        0,
        Ogre::PF_R8G8B8,
        Ogre::TU_RENDERTARGET | Ogre::TU_STATIC_WRITE_ONLY
    );

    Ogre::TexturePtr scene = texture_manager.createManual(
        rt_in_scene_name,
        texture_group_name,
        Ogre::TEX_TYPE_2D,
        viewport.getActualWidth(),
        viewport.getActualHeight(),
        0,
        Ogre::PF_R8G8B8,
        Ogre::TU_RENDERTARGET | Ogre::TU_STATIC_WRITE_ONLY
    );
    return std::array{normal_depth_rough, scene, temp};
}

static auto ssr_compositor_create_pipelines(ssr_compositor &self, Ogre::CompositorManager &composer) {
    Ogre::CompositorPtr compositor = composer.create(
        self.ssr.name,
        Ogre::ResourceGroupManager::DEFAULT_RESOURCE_GROUP_NAME
    ); {
        Ogre::CompositionTechnique *pipeline = compositor->createTechnique(); {
            auto &out_ndr_texture = *pipeline->createTextureDefinition(rt_out_ndr_name); {
                out_ndr_texture.width = 0;
                out_ndr_texture.height = 0;
                out_ndr_texture.formatList.push_back(Ogre::PF_FLOAT32_RGBA);
            }

            auto &in_scene_texture = *pipeline->createTextureDefinition(rt_in_scene_name); {
                in_scene_texture.width = 0;
                in_scene_texture.height = 0;
                in_scene_texture.formatList.push_back(Ogre::PF_R8G8B8);
            }

            auto &in_out_temp_texture = *pipeline->createTextureDefinition(rt_in_out_temp_name); {
                in_out_temp_texture.width = 0;
                in_out_temp_texture.height = 0;
                in_out_temp_texture.formatList.push_back(Ogre::PF_R8G8B8);
            }

            // copy scene colour
            {
                Ogre::CompositionTargetPass &pass_scene = *pipeline->createTargetPass();
                pass_scene.setInputMode(Ogre::CompositionTargetPass::IM_PREVIOUS);
                pass_scene.setOutputName(rt_in_scene_name);
            }
            // clear normal_depth_rough
            {
                Ogre::CompositionTargetPass &pass_clear = *pipeline->createTargetPass();
                pass_clear.setInputMode(Ogre::CompositionTargetPass::IM_NONE);
                pass_clear.setOutputName(rt_out_ndr_name); {
                    Ogre::CompositionPass *pass = pass_clear.createPass(Ogre::CompositionPass::PT_CLEAR);
                    pass->setClearColour(Ogre::ColourValue(0,0,1,1));
                    pass->setClearDepth(1.0f);
                    pass->setClearBuffers(Ogre::FBT_COLOUR | Ogre::FBT_DEPTH);
                }
            }
            // render scene normal, depth and rough
            {
                Ogre::CompositionTargetPass &pass_ndr = *pipeline->createTargetPass();
                pass_ndr.setMaterialScheme(scheme_ndr_name);
                pass_ndr.setInputMode(Ogre::CompositionTargetPass::IM_NONE);
                pass_ndr.setOutputName(rt_out_ndr_name); {
                    Ogre::CompositionPass *pass = pass_ndr.createPass(Ogre::CompositionPass::PT_RENDERSCENE);
                    (void)pass;
                    // pass->setMaterialName(material_ndr_name);
                    // pass->setMaterialScheme(scheme_ndr_name);
                }
            }
            // raytrace reading from normal_depth_rough and scene colour
            {
                Ogre::CompositionTargetPass &pass_raytrace = *pipeline->createTargetPass();
                pass_raytrace.setInputMode(Ogre::CompositionTargetPass::IM_NONE);
                pass_raytrace.setOutputName(rt_in_out_temp_name); {
                    Ogre::CompositionPass *pass = pass_raytrace.createPass(Ogre::CompositionPass::PT_RENDERQUAD);
                    pass->setMaterialName(material_raytrace_name);
                    pass->setInput(0, rt_in_scene_name);
                    pass->setInput(1, rt_out_ndr_name);
                }
            }
            // copyback
            {
                Ogre::CompositionTargetPass &pass_blit = *pipeline->getOutputTargetPass();
                pass_blit.setInputMode(Ogre::CompositionTargetPass::IM_NONE); {
                    Ogre::CompositionPass *pass = pass_blit.createPass(Ogre::CompositionPass::PT_RENDERQUAD);
                    pass->setMaterialName(material_copyback_name);
                    pass->setInput(0, rt_in_out_temp_name);
                }
            }
        }
    }
    return std::array{compositor};
}

template<size_t N>
static auto ssr_compositor_register_pipelines(
    std::array<Ogre::CompositorPtr, N> &pipelines,
    Ogre::CompositorManager &composer,
    Ogre::Viewport &viewport
) {
    for (const Ogre::CompositorPtr &pipeline : pipelines) {
        const auto &name = pipeline->getName();
        composer.addCompositor(&viewport, name);
    }
}

void ssr_compositor::enable_pipelines(Ogre::CompositorManager &composer, Ogre::Viewport &viewport) {
    for (const auto &pipeline : pipelines) {
        const auto &name = pipeline->getName();
        composer.setCompositorEnabled(&viewport, name, true);
    }
}
void ssr_compositor::disable_pipelines(Ogre::CompositorManager &composer, Ogre::Viewport &viewport) {
    for (const auto &pipeline : pipelines) {
        const auto &name = pipeline->getName();
        composer.setCompositorEnabled(&viewport, name, false);
    }
}

Ogre::Technique *ssr_compositor::handleSchemeNotFound(
    unsigned short schemeIndex,
    const Ogre::String &schemeName,
    Ogre::Material *originalMaterial,
    unsigned short lodIndex,
    const Ogre::Renderable *rend
) {
    (void)schemeIndex;
    (void)lodIndex;
    (void)rend;
    
    // source: https://forums.ogre3d.org/viewtopic.php?p=551751#p551751
    Ogre::ResourcePtr res = Ogre::MaterialManager::getSingleton().load(
        material_ndr_name,
        Ogre::ResourceGroupManager::DEFAULT_RESOURCE_GROUP_NAME
    );
    Ogre::MaterialPtr material = Ogre::static_pointer_cast<Ogre::Material>(res);

    Ogre::RTShader::ShaderGenerator& rtShaderGen = Ogre::RTShader::ShaderGenerator::getSingleton();
    for (unsigned short i=0; i< originalMaterial->getTechnique(0)->getNumPasses(); ++i) {
        rtShaderGen.validateMaterial(scheme_ndr_name, *originalMaterial);
        // Grab the generated technique.
        for(Ogre::Technique* curTech : originalMaterial->getTechniques()) {
            if (curTech->getSchemeName() == schemeName) {
                return curTech;
            }
        }
    }

    Ogre::Technique &technique_ndr = *originalMaterial->createTechnique();
    technique_ndr.setSchemeName(schemeName);
    Ogre::Pass* pass = technique_ndr.createPass();
    *pass = *material->getTechnique(0)->getPass(0);

    return &technique_ndr;
}

void ssr_compositor::init(Ogre::CompositorManager &composer, Ogre::Viewport &viewport) {
    Ogre::MaterialManager::getSingleton().addListener(this, scheme_ndr_name);
    composer.registerCompositorLogic(ssr.name, &ssr);

    const auto [ndr, scene, temp] = ssr_compositor_init_textures(
        Ogre::TextureManager::getSingleton(),
        viewport
    );
    normal_depth_rough = ndr;
    this->scene = scene;
    this->temp = temp;

    const auto [compositor] = ssr_compositor_create_pipelines(*this, composer);
    pipelines[0] = compositor;

    ssr_compositor_register_pipelines(pipelines, composer, viewport);
    disable_pipelines(composer, viewport);
}
void ssr_compositor::deinit(Ogre::CompositorManager &composer, Ogre::TextureManager &texture_manager) {
    Ogre::MaterialManager::getSingleton().removeListener(this, scheme_ndr_name);
    composer.unregisterCompositorLogic(ssr.name);
    texture_manager.remove(normal_depth_rough->getName(), texture_group_name);
    texture_manager.remove(scene->getName(), texture_group_name);
    texture_manager.remove(temp->getName(), texture_group_name);
}
