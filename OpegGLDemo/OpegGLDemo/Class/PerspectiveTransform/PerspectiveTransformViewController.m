//
//  PerspectiveTransformViewController.m
//  OpegGLDemo
//
//  Created by 范杨 on 2018/7/2.
//  Copyright © 2018年 RPGLiker. All rights reserved.
//

#import "PerspectiveTransformViewController.h"
#import <GLKit/GLKit.h>
#import "AGLKVertexAttribArrayBuffer.h"
#import "PerspectiveTransformSphere.h"

@interface PerspectiveTransformViewController ()<GLKViewDelegate>

@property (strong, nonatomic) GLKBaseEffect *baseEffect;
@property (strong, nonatomic) AGLKVertexAttribArrayBuffer *vertexPositionBuffer;
@property (strong, nonatomic) AGLKVertexAttribArrayBuffer *vertexNormalBuffer;
@property (strong, nonatomic) AGLKVertexAttribArrayBuffer *vertexTextureCoordBuffer;
@property (strong, nonatomic) GLKTextureInfo *earthTextureInfo;
@property (strong, nonatomic) GLKTextureInfo *moonTextureInfo;
@property (nonatomic) GLKMatrixStackRef modelviewMatrixStack;
@property (nonatomic) GLfloat earthRotationAngleDegrees;
@property (nonatomic) GLfloat moonRotationAngleDegrees;
@property (strong, nonatomic) GLKView *glkView;
@property (strong, nonatomic) CADisplayLink *displayLink;
@end

@implementation PerspectiveTransformViewController

static const GLfloat kSceneEarthAxialTiltDeg = 23.5f;
static const GLfloat kSceneDaysPerMoonOrbit = 28.0f;
static const GLfloat kSceneMoonRadiusFractionOfEarth = 0.25;
static const GLfloat kSceneMoonDistanceFromEarth = 3.0;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    //创建矩阵堆栈
    self.modelviewMatrixStack = GLKMatrixStackCreate(kCFAllocatorDefault);
    
    GLKView *glkView = [[GLKView alloc] initWithFrame:CGRectMake(50, 0, 400, 300)];
    glkView.delegate = self;
    self.glkView = glkView;
    [self.view addSubview:glkView];
    glkView.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    [EAGLContext setCurrentContext:glkView.context];
    
    self.baseEffect = [[GLKBaseEffect alloc] init];
    
    [self configureLight];
    
    //整个场景坐标系
    self.baseEffect.transform.projectionMatrix = GLKMatrix4MakeOrtho(-1.0 * 4.0 / 3.0,//left
                                                                     1.0 * 4.0 / 3.0,//right
                                                                     -1.0,//bottom
                                                                     1.0,//top
                                                                     1.0,//nearZ
                                                                     120.0);//farZ
    
    //场景内模型显示位置坐标系
    self.baseEffect.transform.modelviewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, -5.0);
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    
    self.vertexPositionBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:(3 * sizeof(GLfloat))
                                                                         numberOfVertices:sizeof(perspectiveTransformSphereVerts) / (3 * sizeof(GLfloat))
                                                                                     data:perspectiveTransformSphereVerts
                                                                                    usage:GL_STATIC_DRAW];
    self.vertexNormalBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:(3 * sizeof(GLfloat))
                                                                       numberOfVertices:sizeof(perspectiveTransformSphereNormals) / (3 * sizeof(GLfloat))
                                                                                   data:perspectiveTransformSphereNormals
                                                                                  usage:GL_STATIC_DRAW];
    self.vertexTextureCoordBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:(2 * sizeof(GLfloat))
                                                                             numberOfVertices:sizeof(perspectiveTransformSphereTexCoords) / (2 * sizeof(GLfloat))
                                                                                         data:perspectiveTransformSphereTexCoords
                                                                                        usage:GL_STATIC_DRAW];
    
    // Setup Earth texture
    CGImageRef earthImageRef = [[UIImage imageNamed:@"Earth512x256.jpg"] CGImage];
    _earthTextureInfo = [GLKTextureLoader textureWithCGImage:earthImageRef
                                                     options:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES],GLKTextureLoaderOriginBottomLeft, nil]
                                                       error:NULL];
    
    // Setup Moon texture
    CGImageRef moonImageRef = [[UIImage imageNamed:@"Moon256x128.png"] CGImage];
    _moonTextureInfo = [GLKTextureLoader textureWithCGImage:moonImageRef
                                                    options:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES],GLKTextureLoaderOriginBottomLeft, nil]
                                                      error:NULL];
    
    //用新矩阵替换顶部矩阵
    GLKMatrixStackLoadMatrix4(self.modelviewMatrixStack,
                              self.baseEffect.transform.modelviewMatrix);
    
    //初始化月球旋转角度
    self.moonRotationAngleDegrees = -20.0f;
    
    //定时绘制,觉得旋转速度快的话,可以降低glkview delegate 中的变化幅度
    self.displayLink = [CADisplayLink displayLinkWithTarget:self.glkView selector:@selector(display)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)dealloc{
    
    [EAGLContext setCurrentContext:self.glkView.context];
    
    // Delete buffers that aren't needed when view is unloaded
    self.vertexPositionBuffer = nil;
    self.vertexNormalBuffer = nil;
    self.vertexTextureCoordBuffer = nil;
    
    // Stop using the context created in -viewDidLoad
    self.glkView.context = nil;
    [EAGLContext setCurrentContext:nil];
    
    CFRelease(self.modelviewMatrixStack);
    self.modelviewMatrixStack = NULL;
    
    [self.displayLink invalidate];
    self.displayLink = nil;
}

//支持旋转
-(BOOL)shouldAutorotate{
    return YES;
}
//
//支持的方向
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscapeLeft;
}

//一开始的方向  很重要
-(UIInterfaceOrientation)preferredInterfaceOrientationForPresentation{
    return UIInterfaceOrientationLandscapeLeft;
}

- (void)drawEarth
{
    self.baseEffect.texture2d0.name = _earthTextureInfo.name;
    self.baseEffect.texture2d0.target = _earthTextureInfo.target;
    
    //将矩阵放入栈中缓存,对矩阵进行一些列操作,得到新的矩阵,最后再将原来的矩阵从栈中弹出
    GLKMatrixStackPush(self.modelviewMatrixStack);
    GLKMatrixStackRotate(   // Rotate (tilt Earth's axis)
                         self.modelviewMatrixStack,
                         GLKMathDegreesToRadians(kSceneEarthAxialTiltDeg),
                         1.0, 0.0, 0.0);
    GLKMatrixStackRotate(   // Rotate about Earth's axis
                         self.modelviewMatrixStack,
                         GLKMathDegreesToRadians(_earthRotationAngleDegrees),
                         0.0, 1.0, 0.0);
    self.baseEffect.transform.modelviewMatrix = GLKMatrixStackGetMatrix4(self.modelviewMatrixStack);
    [self.baseEffect prepareToDraw];
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_TRIANGLES
                                           startVertexIndex:0
                                           numberOfVertices:perspectiveTransformSphereNumVerts];
    GLKMatrixStackPop(self.modelviewMatrixStack);
    
    self.baseEffect.transform.modelviewMatrix = GLKMatrixStackGetMatrix4(self.modelviewMatrixStack);
}

- (void)drawMoon
{
    self.baseEffect.texture2d0.name = _moonTextureInfo.name;
    self.baseEffect.texture2d0.target = _moonTextureInfo.target;
    
    GLKMatrixStackPush(self.modelviewMatrixStack);
    
    GLKMatrixStackRotate(   // Rotate to position in orbit
                         self.modelviewMatrixStack,
                         GLKMathDegreesToRadians(_moonRotationAngleDegrees),
                         0.0, 1.0, 0.0);
    GLKMatrixStackTranslate(// Translate to distance from Earth
                            self.modelviewMatrixStack,
                            0.0, 0.0, kSceneMoonDistanceFromEarth);
    GLKMatrixStackScale(    // Scale to size of Moon
                        self.modelviewMatrixStack,
                        kSceneMoonRadiusFractionOfEarth,
                        kSceneMoonRadiusFractionOfEarth,
                        kSceneMoonRadiusFractionOfEarth);
    GLKMatrixStackRotate(   // Rotate Moon on its own axis
                         self.modelviewMatrixStack,
                         GLKMathDegreesToRadians(_moonRotationAngleDegrees),
                         0.0, 1.0, 0.0);
    
    self.baseEffect.transform.modelviewMatrix = GLKMatrixStackGetMatrix4(self.modelviewMatrixStack);
    
    [self.baseEffect prepareToDraw];
    
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_TRIANGLES
                                           startVertexIndex:0
                                           numberOfVertices:perspectiveTransformSphereNumVerts];
    
    GLKMatrixStackPop(self.modelviewMatrixStack);
    
    self.baseEffect.transform.modelviewMatrix = GLKMatrixStackGetMatrix4(self.modelviewMatrixStack);
}

/**
 设置灯光,"太阳"
 */
- (void)configureLight
{
    self.baseEffect.light0.enabled = GL_TRUE;
    self.baseEffect.light0.diffuseColor = GLKVector4Make(1.0f, // Red
                                                         1.0f, // Green
                                                         1.0f, // Blue
                                                         1.0f);// Alpha
    self.baseEffect.light0.position = GLKVector4Make(1.0f,
                                                     0.0f,
                                                     0.8f,
                                                     0.0f);
    self.baseEffect.light0.ambientColor = GLKVector4Make(0.2f, // Red
                                                         0.2f, // Green
                                                         0.2f, // Blue
                                                         1.0f);// Alpha
}

#pragma mark - delegate
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    // Update the angles every frame to animate
    // (one day every 60 display updates)
    self.earthRotationAngleDegrees += 360.0f / 60.0f;
    self.moonRotationAngleDegrees += (360.0f / 60.0f) / kSceneDaysPerMoonOrbit;
    
    glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
    
    [self.vertexPositionBuffer prepareToDrawWithAttrib:GLKVertexAttribPosition
                                    numberOfCordinates:3
                                          attribOffset:0
                                          shouldEnable:YES];
    
    [self.vertexNormalBuffer prepareToDrawWithAttrib:GLKVertexAttribNormal
                                  numberOfCordinates:3
                                        attribOffset:0
                                        shouldEnable:YES];
    
    [self.vertexTextureCoordBuffer prepareToDrawWithAttrib:GLKVertexAttribTexCoord0
                                        numberOfCordinates:2
                                              attribOffset:0
                                              shouldEnable:YES];
    
    [self drawEarth];
    [self drawMoon];
    
    glEnable(GL_DEPTH_TEST);
}
#pragma mark - target
- (IBAction)didClickCloseButton:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (IBAction)didClickScaleButton:(UISwitch *)sender {
    GLfloat aspectRatio = (float)(self.glkView).drawableWidth /(float)(self.glkView).drawableHeight;
    
    if([sender isOn])
    {
        //透视投影变换,远面较大
        self.baseEffect.transform.projectionMatrix = GLKMatrix4MakeFrustum(-1.0 * aspectRatio,
                                                                           1.0 * aspectRatio,
                                                                           -1.0,
                                                                           1.0,
                                                                           1.0,
                                                                           120.0);//far必须是正的,且大于near
    }else{
        //正视投影变换,近面较大
        self.baseEffect.transform.projectionMatrix =GLKMatrix4MakeOrtho(-1.0 * aspectRatio,
                                                                        1.0 * aspectRatio,
                                                                        -1.0,
                                                                        1.0,
                                                                        1.0,
                                                                        120.0);
    }
    [self.glkView display];
}

@end
