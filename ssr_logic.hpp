#include <OgrePrerequisites.h>
#include <OgreCompositorLogic.h>
#include <OgreCompositorInstance.h>

#include "ListenerFactoryLogic.h"
#include <string_view>

struct ssr_logic : public ListenerFactoryLogic {
    static const std::string name;
protected:
    Ogre::CompositorInstance::Listener* createListener(Ogre::CompositorInstance* instance) override;
};