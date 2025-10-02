#include "SinbadExample.hpp"
#include "ssr_compositor.hpp"

using namespace std;
using namespace Ogre;


bool SinbadExample::keyPressed(const OgreBites::KeyboardEvent& evt) {

    // ESC key finished the rendering...
    if (evt.keysym.sym == SDLK_ESCAPE) {
        getRoot()->queueEndRendering();
    }

    return true;
}


void SinbadExample::shutdown() {

    mShaderGenerator->removeSceneManager(mSM);
    mSM->removeRenderQueueListener(mOverlaySystem);

    mRoot->destroySceneManager(mSM);

    delete mTrayMgr;  mTrayMgr = nullptr;
    delete mCamMgr; mCamMgr = nullptr;

    // do not forget to call the base 
    OgreBites::ApplicationContext::shutdown();
}

void SinbadExample::setup(void) {

    // do not forget to call the base first
    OgreBites::ApplicationContext::setup();
    // mRoot->showConfigDialog(nullptr);

    // Create the scene manager
    mSM = mRoot->createSceneManager();

    // Register our scene with the RTSS
    mShaderGenerator->addSceneManager(mSM);
        
    mSM->addRenderQueueListener(mOverlaySystem);
    //mTrayMgr = new OgreBites::TrayManager("TrayGUISystem", mWindow.render);
    mTrayMgr = new OgreBites::TrayManager("TrayGUISystem", getRenderWindow());
    mTrayMgr->showFrameStats(OgreBites::TL_BOTTOMLEFT);
    addInputListener(mTrayMgr);

    // Adds the listener for this object
    addInputListener(this);
    setupScene();
}

// static ssr_compositor ssr{};

void SinbadExample::setupScene(void) {

    //------------------------------------------------------------------------
    // Creating the camera

    Camera* cam = mSM->createCamera("Cam");
    cam->setNearClipDistance(1);
    cam->setFarClipDistance(100);
    cam->setAutoAspectRatio(true);
    //cam->setPolygonMode(Ogre::PM_WIREFRAME);

    mCamNode = mSM->getRootSceneNode()->createChildSceneNode("nCam");
    mCamNode->attachObject(cam);

    mCamNode->setPosition(0, 0, 1000);
    mCamNode->lookAt(Ogre::Vector3(0, 0, 0), Ogre::Node::TS_WORLD);

    // and tell it to render into the main window
    Viewport* vp = getRenderWindow()->addViewport(cam);
    ssr_compositor &ssr = *new ssr_compositor{};
    auto &composer = Ogre::CompositorManager::getSingleton();
    ssr.init(composer, *vp);
    ssr.enable_pipelines(composer, *vp);

    // TODO
    // Ogre::CompositorManager::getSingleton().addCompositor(vp, "SSR");
    // Ogre::CompositorManager::getSingleton().setCompositorEnabled(vp, "SSR", true);
    // mSM->addListener


    mCamMgr = new OgreBites::CameraMan(mCamNode);
    addInputListener(mCamMgr);
    mCamMgr->setStyle(OgreBites::CS_ORBIT);


    //------------------------------------------------------------------------
    // Creating the light

    //mSM->setAmbientLight(ColourValue(0.5, 0.5, 0.5));
    
    Light* luz = mSM->createLight("Luz");
    luz->setType(Ogre::Light::LT_DIRECTIONAL);
    luz->setDiffuseColour(0.75, 0.75, 0.75);

    mLightNode = mSM->getRootSceneNode()->createChildSceneNode("nLuz");
    mLightNode->attachObject(luz);
    mLightNode->setDirection(Ogre::Vector3(-1, -1, -1));
 

    //------------------------------------------------------------------------
    // Creating Sinbad

    Ogre::Entity* ent = mSM->createEntity("Sinbad.mesh");
    mSinbadNode = mSM->getRootSceneNode()->createChildSceneNode("nSinbad");
    mSinbadNode->attachObject(ent);

    // Show bounding box
    // mSinbadNode->showBoundingBox(true);

    // Set position of Sinbad
    //mSinbadNode->setPosition(x, y, z);

    // Set scale of Sinbad
    //mSinbadNode->setScale(20, 20, 20);

    //mSinbadNode->yaw(Ogre::Degree(-45));
    //mSinbadNode->setVisible(false);    


    //------------------------------------------------------------------------
    // Create a demo scene

    // Ogre::Entity *place = mSM->createEntity("RomanBathLower.mesh");
    // Ogre::SceneNode *placeNode = mSM->getRootSceneNode()->createChildSceneNode("nRomanBathLower");
    // placeNode->attachObject(place);
    // placeNode->setScale(20, 20, 20);

    Ogre::MeshPtr plane = Ogre::MeshManager::getSingleton().createPlane(
        "plane", 
        Ogre::ResourceGroupManager::DEFAULT_RESOURCE_GROUP_NAME,
        Ogre::Plane(Ogre::Vector3::UNIT_Y, 0), 
        15, 15, 4, 4, true,
        1, 4, 4, Ogre::Vector3::UNIT_Z
    );
    Ogre::Entity *planeEnt = mSM->createEntity("Plane", "plane");
    Ogre::SceneNode *planeNode = mSM->getRootSceneNode()->createChildSceneNode("nPlane");
    planeNode->attachObject(planeEnt);
    planeNode->setPosition(0, -5, 0);


    // unit cube to measure
    Ogre::Entity *cube = mSM->createEntity("Cube", "cube.mesh");
    Ogre::SceneNode *cubeNode = mSM->getRootSceneNode()->createChildSceneNode("nCube");
    cubeNode->attachObject(cube);
    cubeNode->setPosition(-5, -4.5, 0);
    cubeNode->setScale(0.01, 0.01, 0.01);
}