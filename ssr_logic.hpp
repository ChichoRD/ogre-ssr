#ifndef SSR_LOGIC_HPP
#define SSR_LOGIC_HPP

#include <OgrePrerequisites.h>
#include <OgreCompositorLogic.h>
#include <OgreCompositorInstance.h>

#include "ListenerFactoryLogic.h"
#include <string_view>

// TODO: use it to edit values at runtime
struct ssr_logic : public ListenerFactoryLogic {
    static const std::string name;
protected:
    Ogre::CompositorInstance::Listener* createListener(Ogre::CompositorInstance* instance) override;
};

#endif