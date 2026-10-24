"""Deterministic Xcode project; no external generator/dependency is required."""
from pathlib import Path
import hashlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1] / 'TodoWallpaper'
objects = {}

def identifier(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

def obj(key, isa, **values):
    token = identifier(key)
    objects[token] = {'isa':isa, **values}
    return token

def quote(value):
    return '"' + str(value).replace('\\','\\\\').replace('"','\\"') + '"'

def dump(value, depth=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('    '*(depth+1) + quote(k) + ' = ' + dump(v,depth+1) + ';\n' for k,v in value.items()) + '    '*depth + '}'
    if isinstance(value, list):
        return '(' + ', '.join(dump(v,depth) for v in value) + ')'
    return quote(value)

groups, builds = [], []
for folder in ['App','Core']:
    refs = []
    for path in sorted((ROOT/folder).glob('*')):
        if path.suffix not in ['.swift','.plist']:
            continue
        ref = obj(str(path.relative_to(ROOT)), 'PBXFileReference', path=path.name,
                  lastKnownFileType='sourcecode.swift' if path.suffix == '.swift' else 'text.plist.xml', sourceTree='<group>')
        refs.append(ref)
        if path.suffix == '.swift':
            builds.append(obj('build:'+path.name,'PBXBuildFile',fileRef=ref))
    groups.append(obj('group:'+folder,'PBXGroup',children=refs,path=folder,sourceTree='<group>'))
product = obj('product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='TodoWallpaper.app',sourceTree='BUILT_PRODUCTS_DIR')
products = obj('products','PBXGroup',children=[product],name='Products',sourceTree='<group>')
main_group = obj('main-group','PBXGroup',children=groups+[products],sourceTree='<group>')
phases = [obj('sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0)]
for key, isa in [('frameworks','PBXFrameworksBuildPhase'),('resources','PBXResourcesBuildPhase')]:
    phases.append(obj(key,isa,buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0))
project_configs, target_configs = [], []
for name in ['Debug','Release']:
    project_configs.append(obj('project:'+name,'XCBuildConfiguration',name=name,buildSettings={
        'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SDKROOT':'iphoneos',
        'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O'}))
    target_configs.append(obj('target:'+name,'XCBuildConfiguration',name=name,buildSettings={
        'CODE_SIGN_STYLE':'Automatic','PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'org.todowallpaper.app',
        'CURRENT_PROJECT_VERSION':'1001','MARKETING_VERSION':'0.1.0',
        'GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_FILE':'App/Info.plist',
        'INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES',
        'TARGETED_DEVICE_FAMILY':'1,2','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator',
        'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']}))
project_list = obj('project-configs','XCConfigurationList',buildConfigurations=project_configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target_list = obj('target-configs','XCConfigurationList',buildConfigurations=target_configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target = obj('target','PBXNativeTarget',buildConfigurationList=target_list,buildPhases=phases,buildRules=[],dependencies=[],name='TodoWallpaper',productName='TodoWallpaper',productReference=product,productType='com.apple.product-type.application')
project = obj('project','PBXProject',attributes={'LastUpgradeCheck':'2600'},buildConfigurationList=project_list,
              compatibilityVersion='Xcode 14.0',developmentRegion='zh_CN',hasScannedForEncodings=0,
              knownRegions=['zh_CN','en','Base'],mainGroup=main_group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target])
directory = ROOT / 'TodoWallpaper.xcodeproj'
directory.mkdir(exist_ok=True)
(directory/'project.pbxproj').write_text('// !$*UTF8*$!\n' + dump({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
scheme = ET.Element('Scheme',LastUpgradeVersion='2600',version='1.3')
action = ET.SubElement(scheme,'BuildAction',parallelizeBuildables='YES',buildImplicitDependencies='YES')
entries = ET.SubElement(action,'BuildActionEntries')
entry = ET.SubElement(entries,'BuildActionEntry',buildForTesting='YES',buildForRunning='YES',buildForProfiling='YES',buildForArchiving='YES',buildForAnalyzing='YES')
ET.SubElement(entry,'BuildableReference',BuildableIdentifier='primary',BlueprintIdentifier=target,BuildableName='TodoWallpaper.app',BlueprintName='TodoWallpaper',ReferencedContainer='container:TodoWallpaper.xcodeproj')
ET.SubElement(scheme,'ArchiveAction',buildConfiguration='Release',revealArchiveInOrganizer='YES')
schemes = directory/'xcshareddata/xcschemes'
schemes.mkdir(parents=True,exist_ok=True)
ET.ElementTree(scheme).write(schemes/'TodoWallpaper.xcscheme',encoding='utf-8',xml_declaration=True)
print('Generated TodoWallpaper.xcodeproj and shared Scheme')
