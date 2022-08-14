#import <Foundation/Foundation.h>
#import "asvg_File_Import.h"
#import <assert.h>
#import <iostream>
#import "lunasvg.h"

static unsigned int atom(std::string str) {
    assert(str.length()==4);
    unsigned char *key =(unsigned char *)str.c_str();
    return key[0]<<24|key[1]<<16|key[2]<<8|key[3];
}

static unsigned short swapU16(unsigned short n) {
    return ((n>>8)&0xFF)|((n&0xFF)<<8);
}

static unsigned int swapU32(unsigned int n) {
    return ((n>>24)&0xFF)|(((n>>16)&0xFF)<<8)|(((n>>8)&0xFF)<<16)|((n&0xFF)<<24);
}

static unsigned short toU16(unsigned char *p) {
    return *((unsigned short *)p);
}

static unsigned int toU32(unsigned char *p) {
    return *((unsigned int *)p);
}

#if IMPORTMOD_VERSION <= IMPORTMOD_VERSION_9
typedef PrSDKPPixCacheSuite2 PrCacheSuite;
#define PrCacheVersion kPrSDKPPixCacheSuiteVersion2
#else
typedef PrSDKPPixCacheSuite PrCacheSuite;
#define PrCacheVersion kPrSDKPPixCacheSuiteVersion
#endif

typedef struct {
    csSDK_int32 importerID;
    csSDK_int32 fileType;
    csSDK_int32 width;
    csSDK_int32 height;
    csSDK_int32 frameRateNum;
    csSDK_int32 frameRateDen;
    PlugMemoryFuncsPtr memFuncs;
    SPBasicSuite *BasicSuite;
    PrSDKPPixCreatorSuite *PPixCreatorSuite;
    PrCacheSuite *PPixCacheSuite;
    PrSDKPPixSuite *PPixSuite;
    PrSDKTimeSuite *TimeSuite;
    PrSDKImporterFileManagerSuite *FileSuite;
    
    unsigned long *frame_head;
    unsigned int *frame_size;
    
} ImporterLocalRec8, *ImporterLocalRec8Ptr, **ImporterLocalRec8H;

static prMALError SDKInit(imStdParms *stdParms, imImportInfoRec *importInfo) {
    importInfo->canSave = kPrFalse; // Can 'save as' files to disk, real file only.
    importInfo->canDelete = kPrFalse; // File importers only, use if you only if you have child files
    importInfo->canCalcSizes = kPrFalse; // These are for importers that look at a whole tree of files so Premiere doesn't know about all of them.
    importInfo->canTrim = kPrFalse;
    importInfo->hasSetup = kPrFalse; // Set to kPrTrue if you have a setup dialog
    importInfo->setupOnDblClk = kPrFalse; // If user dbl-clicks file you imported, pop your setup dialog
    importInfo->dontCache = kPrFalse; // Don't let Premiere cache these files
    importInfo->keepLoaded = kPrFalse; // If you MUST stay loaded use, otherwise don't: play nice
    importInfo->priority = 0;
    importInfo->avoidAudioConform = kPrFalse; //kPrTrue; // If I let Premiere conform the audio, I get silence when I try to play it in the program.  Seems like a bug to me.

    return malNoError;
}

static prMALError SDKGetIndFormat(imStdParms *stdParms, csSDK_size_t index, imIndFormatRec *SDKIndFormatRec) {
        
    prMALError result = malNoError;
    char formatname[255] = "asvg";
    char shortname[32] = "asvg";
    char platformXten[256] = "asvg\0";

    switch(index) {
        
        case 0:
            SDKIndFormatRec->filetype = 'asvg';

            SDKIndFormatRec->canWriteTimecode = kPrFalse;
            SDKIndFormatRec->canWriteMetaData = kPrFalse;

            SDKIndFormatRec->flags = xfCanImport|xfIsMovie;
           
            strcpy(SDKIndFormatRec->FormatName,formatname); // The Long name of the importer
            strcpy(SDKIndFormatRec->FormatShortName,shortname); // The short (menu name) of the importer
            strcpy(SDKIndFormatRec->PlatformExtension,platformXten); // The 3 letter extension

            break;

        default:
            result = imBadFormatIndex;
    }

    return result;
}

prMALError SDKOpenFile8(imStdParms *stdParms, imFileRef *SDKfileRef, imFileOpenRec8 *SDKfileOpenRec8) {
        
    prMALError result = malNoError;

    ImporterLocalRec8H localRecH = NULL;
    ImporterLocalRec8Ptr localRecP = NULL;

    if(SDKfileOpenRec8->privatedata) {
        localRecH = (ImporterLocalRec8H)SDKfileOpenRec8->privatedata;
        stdParms->piSuites->memFuncs->lockHandle(reinterpret_cast<char**>(localRecH));
        localRecP = reinterpret_cast<ImporterLocalRec8Ptr>(*localRecH);
    }
    else {
        
        localRecH = (ImporterLocalRec8H)stdParms->piSuites->memFuncs->newHandle(sizeof(ImporterLocalRec8));
        SDKfileOpenRec8->privatedata = (PrivateDataPtr)localRecH;
        stdParms->piSuites->memFuncs->lockHandle(reinterpret_cast<char**>(localRecH));
        localRecP = reinterpret_cast<ImporterLocalRec8Ptr>(*localRecH);
        
        // Acquire needed suites
        localRecP->memFuncs = stdParms->piSuites->memFuncs;
        localRecP->BasicSuite = stdParms->piSuites->utilFuncs->getSPBasicSuite();
        if(localRecP->BasicSuite) {
            localRecP->BasicSuite->AcquireSuite(kPrSDKPPixCreatorSuite,kPrSDKPPixCreatorSuiteVersion,(const void**)&localRecP->PPixCreatorSuite);
            localRecP->BasicSuite->AcquireSuite(kPrSDKPPixCacheSuite,PrCacheVersion,(const void**)&localRecP->PPixCacheSuite);
            localRecP->BasicSuite->AcquireSuite(kPrSDKPPixSuite, kPrSDKPPixSuiteVersion,(const void**)&localRecP->PPixSuite);
            localRecP->BasicSuite->AcquireSuite(kPrSDKTimeSuite, kPrSDKTimeSuiteVersion,(const void**)&localRecP->TimeSuite);
            localRecP->BasicSuite->AcquireSuite(kPrSDKImporterFileManagerSuite, kPrSDKImporterFileManagerSuiteVersion,(const void**)&localRecP->FileSuite);
        }

        localRecP->importerID = SDKfileOpenRec8->inImporterID;
        localRecP->fileType = SDKfileOpenRec8->fileinfo.filetype;
                
        localRecP->frame_head = nullptr;
        localRecP->frame_size = nullptr;
    }

    SDKfileOpenRec8->fileinfo.fileref = *SDKfileRef = reinterpret_cast<imFileRef>(imInvalidHandleValue);

    if(localRecP) {
        const prUTF16Char *path = SDKfileOpenRec8->fileinfo.filepath;
   
        FSIORefNum refNum = CAST_REFNUM(imInvalidHandleValue);
                
        CFStringRef filePathCFSR = CFStringCreateWithCharacters(NULL,path,prUTF16CharLength(path));
                                                    
        CFURLRef filePathURL = CFURLCreateWithFileSystemPath(NULL,filePathCFSR,kCFURLPOSIXPathStyle,false);
        
        if(filePathURL!=NULL) {
            FSRef fileRef;
            Boolean success = CFURLGetFSRef(filePathURL,&fileRef);
            
            if(success) {
                HFSUniStr255 dataForkName;
                FSGetDataForkName(&dataForkName);
                FSOpenFork(&fileRef,dataForkName.length,dataForkName.unicode,fsRdPerm,&refNum);
            }
                                        
            CFRelease(filePathURL);
        }
                                    
        CFRelease(filePathCFSR);

        if(CAST_FILEREF(refNum)!=imInvalidHandleValue) {
            SDKfileOpenRec8->fileinfo.fileref = *SDKfileRef = CAST_FILEREF(refNum);
        }
        else {
            result = imFileOpenFailed;
        }
    }
    
    // close file and delete private data if we got a bad file
    if(result != malNoError) {
        if(SDKfileOpenRec8->privatedata) {
            stdParms->piSuites->memFuncs->disposeHandle(reinterpret_cast<PrMemoryHandle>(SDKfileOpenRec8->privatedata));
            SDKfileOpenRec8->privatedata = NULL;
        }
    }
    else {
        stdParms->piSuites->memFuncs->unlockHandle(reinterpret_cast<char**>(SDKfileOpenRec8->privatedata));
    }

    return result;
}

static prMALError SDKQuietFile(imStdParms *stdParms, imFileRef *SDKfileRef, void *privateData) {
        
    // "Quiet File" really means close the file handle, but we're still
    // using it and might open it again, so hold on to any stored data
    // structures you don't want to re-create.

    // If file has not yet been closed
    if(SDKfileRef&&*SDKfileRef!=imInvalidHandleValue) {
        ImporterLocalRec8H ldataH = reinterpret_cast<ImporterLocalRec8H>(privateData);

        stdParms->piSuites->memFuncs->lockHandle(reinterpret_cast<char**>(ldataH));

        // ImporterLocalRec8Ptr localRecP = reinterpret_cast<ImporterLocalRec8Ptr>( *ldataH );

        stdParms->piSuites->memFuncs->unlockHandle(reinterpret_cast<char**>(ldataH));

        FSCloseFork((FSIORefNum)CAST_REFNUM(*SDKfileRef) );
    
        *SDKfileRef = imInvalidHandleValue;
    }

    return malNoError;
}

static prMALError SDKCloseFile(imStdParms *stdParms, imFileRef *SDKfileRef, void *privateData) {
        
    ImporterLocalRec8H ldataH = reinterpret_cast<ImporterLocalRec8H>(privateData);
    
    // If file has not yet been closed
    if(SDKfileRef && *SDKfileRef!=imInvalidHandleValue) {
        SDKQuietFile(stdParms,SDKfileRef,privateData);
    }

    // Remove the privateData handle.
    // CLEANUP - Destroy the handle we created to avoid memory leaks
    if(ldataH&&*ldataH&&(*ldataH)->BasicSuite) {
        stdParms->piSuites->memFuncs->lockHandle(reinterpret_cast<char**>(ldataH));

        ImporterLocalRec8Ptr localRecP = reinterpret_cast<ImporterLocalRec8Ptr>(*ldataH);

        localRecP->BasicSuite->ReleaseSuite(kPrSDKPPixCreatorSuite,kPrSDKPPixCreatorSuiteVersion);
        localRecP->BasicSuite->ReleaseSuite(kPrSDKPPixCacheSuite,PrCacheVersion);
        localRecP->BasicSuite->ReleaseSuite(kPrSDKPPixSuite,kPrSDKPPixSuiteVersion);
        localRecP->BasicSuite->ReleaseSuite(kPrSDKTimeSuite,kPrSDKTimeSuiteVersion);
        localRecP->BasicSuite->ReleaseSuite(kPrSDKImporterFileManagerSuite, kPrSDKImporterFileManagerSuiteVersion);
        
        stdParms->piSuites->memFuncs->disposeHandle(reinterpret_cast<PrMemoryHandle>(ldataH));
    }

    return malNoError;
}

static prMALError SDKGetIndPixelFormat(imStdParms *stdParms, csSDK_size_t idx,imIndPixelFormatRec *SDKIndPixelFormatRec) {
    prMALError result = malNoError;
    switch(idx) {
        case 0:
            SDKIndPixelFormatRec->outPixelFormat = PrPixelFormat_BGRA_4444_8u;
            break;
    
        default:
            result = imBadFormatIndex;
            break;
    }
    return result;
}

// TODO: Support imDataRateAnalysis and we'll get a pretty graph in the Properties panel!
// Sounds like a good task for someone who wants to contribute to this open source project.

static prMALError SDKAnalysis(imStdParms *stdParms, imFileRef SDKfileRef, imAnalysisRec *SDKAnalysisRec) {
        
    // Is this all I'm supposed to do here?
    // The string shows up in the properties dialog.

    const char *properties_messsage = "Hi there";
    if(SDKAnalysisRec->buffersize > strlen(properties_messsage)) {
        strcpy(SDKAnalysisRec->buffer, properties_messsage);
    }
    return malNoError;
}

prMALError SDKGetInfo8(imStdParms *stdParms, imFileAccessRec8 *fileAccessInfo8, imFileInfoRec8 *SDKFileInfo8) {
    
    prMALError result = malNoError;
    
    SDKFileInfo8->vidInfo.supportsAsyncIO = kPrFalse;
    SDKFileInfo8->vidInfo.supportsGetSourceVideo = kPrTrue;
    SDKFileInfo8->vidInfo.hasPulldown = kPrFalse;
    SDKFileInfo8->hasDataRate = kPrFalse;
    
    // private data
    assert(SDKFileInfo8->privatedata);
    ImporterLocalRec8H ldataH = reinterpret_cast<ImporterLocalRec8H>(SDKFileInfo8->privatedata);
    stdParms->piSuites->memFuncs->lockHandle(reinterpret_cast<char**>(ldataH));
    ImporterLocalRec8Ptr localRecP = reinterpret_cast<ImporterLocalRec8Ptr>(*ldataH);
    
    SDKFileInfo8->hasVideo = kPrFalse;
    SDKFileInfo8->hasAudio = kPrFalse;
    
    if(localRecP) {
        
        int frames = 0;
                
        unsigned int buffer = 0;
        ByteCount actualCount = 0;
        
        unsigned long begin = 4*7;
        
        FSReadFork((FSIORefNum)CAST_REFNUM(fileAccessInfo8->fileref),fsFromStart,begin,4,&buffer,&actualCount);
        int offset = swapU32(buffer);
        
        begin+=4;
        FSReadFork((FSIORefNum)CAST_REFNUM(fileAccessInfo8->fileref),fsFromStart,begin,4,&buffer,&actualCount);
        
        if(swapU32(buffer)==atom("mdat")) {
            
            begin+=offset-4;
            FSReadFork((FSIORefNum)CAST_REFNUM(fileAccessInfo8->fileref),fsFromStart,begin,4,&buffer,&actualCount);
            int len = swapU32(buffer);
            
            begin+=4;
            FSReadFork((FSIORefNum)CAST_REFNUM(fileAccessInfo8->fileref),fsFromStart,begin,4,&buffer,&actualCount);
            if(swapU32(buffer)==atom("moov")) {
                                
                unsigned char *moov = new unsigned char[len-8];
                
                FSReadFork((FSIORefNum)CAST_REFNUM(fileAccessInfo8->fileref),fsFromStart,begin,len-8,moov,&actualCount);
                bool key = false;
                
                unsigned long end = len-8;

                unsigned long info_offset[4];
                info_offset[0] = 4*4;
                info_offset[1] = info_offset[0]+4+6+2+2+2+4+4+4;
                info_offset[2] = info_offset[1]+2;
                info_offset[3] = info_offset[2]+4+4+4+2+32+2;
                
                for(unsigned long k=0; k<end-info_offset[3]; k++) {

                    if(swapU32(toU32(moov+k))==atom("stsd")) {
                        
                        if(swapU32(toU32(moov+k+info_offset[0]))==atom("asvg")) {
                            SDKFileInfo8->vidInfo.imageWidth  = swapU16(toU16(moov+k+info_offset[1]));
                            SDKFileInfo8->vidInfo.imageHeight = swapU16(toU16(moov+k+info_offset[2]));
                            key = true;
                            break;
                        }
                    }
                }
            
                if(key) {
                    
                    unsigned int TimeScale = 0;
                    for(int k=0; k<(len-8)-3; k++) {
                        if(swapU32(toU32(moov+k))==atom("mvhd")) {
                            if(k+(4*4)<(len-8)) {
                                TimeScale = swapU32(*((unsigned int *)(moov+k+(4*4))));
                                break;
                            }
                        }
                    }
                                        
                    if(TimeScale>0) {
                        
                        double FPS = 0;
                        for(int k=0; k<(len-8)-3; k++) {
                            if(swapU32(toU32(moov+k))==atom("stts")) {
                                if(k+(4*4)<(len-8)) {
                                    FPS = TimeScale/(double)(swapU32(toU32(moov+k+(4*4))));
                                    SDKFileInfo8->vidScale = TimeScale;
                                    SDKFileInfo8->vidSampleSize = (swapU32(toU32(moov+k+(4*4))));
                                    break;
                                }
                            }
                        }
                                                
                        if(FPS>0) {
                            
                            for(int k=0; k<(len-8)-3; k++) {
                                if(swapU32(toU32(moov+k))==atom("stsz")) {
                                    k+=(4*3);
                                    if(k<(len-8)) {
                                        
                                        unsigned long head = 4*9;
                                        
                                        frames = swapU32(*((unsigned int *)(moov+k)));
                                        
                                        if(localRecP->frame_head) delete[] localRecP->frame_head;
                                        if(localRecP->frame_size) delete[] localRecP->frame_size;

                                        localRecP->frame_head = new unsigned long[frames];
                                        localRecP->frame_size = new unsigned int[frames];
                                        
                                        for(int f=0; f<frames; f++) {
                                            k+=4;
                                            if(k<len-8) {
                                                
                                                unsigned int size = swapU32(toU32(moov+k));
                                                
                                                localRecP->frame_head[f] = head;
                                                localRecP->frame_size[f] = size;

                                                NSLog(@"%ld,%d",head,size);

                                                head+=size;
                                            }
                                        }
                                        
                                        break;
                                    }
                                }
                            }
                        }
                        else {
                            result = imFileOpenFailed;
                        }
                        
                    }
                    else {
                        result = imFileOpenFailed;
                    }
                    
                }
                else {
                    result = imFileOpenFailed;
                }
                
                delete[] moov;
            }
        }
                
        if(frames>0) {
            
            SDKFileInfo8->hasVideo = kPrTrue;
            SDKFileInfo8->vidInfo.subType = PrPixelFormat_BGRA_4444_8u;
            SDKFileInfo8->vidInfo.depth = 32; // for RGB, no A
            SDKFileInfo8->vidInfo.fieldType = prFieldsUnknown; // Matroska talk about DefaultDecodedFieldDuration but...
            SDKFileInfo8->vidInfo.isStill = kPrFalse;
            SDKFileInfo8->vidInfo.noDuration = imNoDurationFalse;
            
            SDKFileInfo8->vidInfo.alphaType = alphaStraight;
            
            SDKFileInfo8->vidDuration = frames * SDKFileInfo8->vidSampleSize;
          
            // store some values we want to get without going to the file
            localRecP->width = SDKFileInfo8->vidInfo.imageWidth;
            localRecP->height = SDKFileInfo8->vidInfo.imageHeight;
            
            localRecP->frameRateNum = SDKFileInfo8->vidScale;
            localRecP->frameRateDen = SDKFileInfo8->vidSampleSize;
          
        }
        else {
            result = imFileOpenFailed;
        }
        
    }
    else {
        result = imFileOpenFailed;
    }
    
    stdParms->piSuites->memFuncs->unlockHandle(reinterpret_cast<char**>(ldataH));
    
    return result;
}

static prMALError SDKPreferredFrameSize(imStdParms *stdparms, imPreferredFrameSizeRec *preferredFrameSizeRec) {
        
    prMALError result = imIterateFrameSizes;
    ImporterLocalRec8H ldataH = reinterpret_cast<ImporterLocalRec8H>(preferredFrameSizeRec->inPrivateData);

    stdparms->piSuites->memFuncs->lockHandle(reinterpret_cast<char**>(ldataH));

    ImporterLocalRec8Ptr localRecP = reinterpret_cast<ImporterLocalRec8Ptr>( *ldataH );

    // TODO: Make sure it really isn't possible to decode a smaller frame
    bool can_shrink = false;

    if(preferredFrameSizeRec->inIndex == 0) {
        preferredFrameSizeRec->outWidth = localRecP->width;
        preferredFrameSizeRec->outHeight = localRecP->height;
    }
    else {
        // we store width and height in private data so we can produce it here
        const int divisor = pow(2.0, preferredFrameSizeRec->inIndex);
        
        if(can_shrink && preferredFrameSizeRec->inIndex < 4 && localRecP->width % divisor == 0 && localRecP->height % divisor == 0 ) {
            preferredFrameSizeRec->outWidth = localRecP->width / divisor;
            preferredFrameSizeRec->outHeight = localRecP->height / divisor;
        }
        else {
            result = malNoError;
        }
    }

    stdparms->piSuites->memFuncs->unlockHandle(reinterpret_cast<char**>(ldataH));

    return result;
}

// Set to the half the size of the number of frames you think Premiere will actually keep in its cache.
//#define FRAME_REACH 60
#define FRAME_REACH 1

static prMALError SDKGetSourceVideo(imStdParms *stdParms, imFileRef fileRef, imSourceVideoRec *sourceVideoRec) {
        
    prMALError result = malNoError;

    // privateData
    ImporterLocalRec8H ldataH = reinterpret_cast<ImporterLocalRec8H>(sourceVideoRec->inPrivateData);
    stdParms->piSuites->memFuncs->lockHandle(reinterpret_cast<char**>(ldataH));
    ImporterLocalRec8Ptr localRecP = reinterpret_cast<ImporterLocalRec8Ptr>( *ldataH );

    PrTime ticksPerSecond = 0;
    localRecP->TimeSuite->GetTicksPerSecond(&ticksPerSecond);
    
    csSDK_int32 theFrame = 0;
    if(localRecP->frameRateDen==0) { // i.e. still frame
        theFrame = 0;
    }
    else {
        PrTime ticksPerFrame = (ticksPerSecond*(PrTime)localRecP->frameRateDen)/(PrTime)localRecP->frameRateNum;
        theFrame = (csSDK_int32)(sourceVideoRec->inFrameTime/ticksPerFrame);
    }

    // Check to see if frame is already in cache
    result = localRecP->PPixCacheSuite->GetFrameFromCache(localRecP->importerID,0,theFrame,1,sourceVideoRec->inFrameFormats,sourceVideoRec->outFrame,NULL,NULL);

    // If frame is not in the cache, read the frame and put it in the cache; otherwise, we're done
    if(result != suiteError_NoError) {
        // ok, we'll read the file - clear error
        result = malNoError;
        
        // get the Premiere buffer
        imFrameFormat *frameFormat = &sourceVideoRec->inFrameFormats[0];
        prRect theRect;
        if(frameFormat->inFrameWidth==0&&frameFormat->inFrameHeight==0) {
            frameFormat->inFrameWidth = localRecP->width;
            frameFormat->inFrameHeight = localRecP->height;
        }
        
        // Windows and MacOS have different definitions of Rects, so use the cross-platform prSetRect
        prSetRect(&theRect,0,0,frameFormat->inFrameWidth,frameFormat->inFrameHeight);
        
        PPixHand ppix;
        localRecP->PPixCreatorSuite->CreatePPix(&ppix,PrPPixBufferAccess_ReadWrite,frameFormat->inPixelFormat,&theRect);
        
        if(frameFormat->inPixelFormat == PrPixelFormat_BGRA_4444_8u) {
            
            char *pixelAddress = nullptr;
            localRecP->PPixSuite->GetPixels(ppix,PrPPixBufferAccess_ReadWrite,&pixelAddress);
            csSDK_int32 rowBytes = 0;
            localRecP->PPixSuite->GetRowBytes(ppix,&rowBytes);
            
            const int w = localRecP->width;
            const int h = localRecP->height;
            
            assert(frameFormat->inFrameWidth==w);
            assert(frameFormat->inFrameHeight==h);
                        
            unsigned long frame_head = localRecP->frame_head[theFrame];
            unsigned int frame_size = localRecP->frame_size[theFrame];
            
            unsigned char *svg = new unsigned char[frame_size];
            
            ByteCount actualCount = 0;
            FSReadFork((FSIORefNum)CAST_REFNUM(fileRef),fsFromStart,frame_head,frame_size,svg,&actualCount);
            
            auto document = lunasvg::Document::loadFromData((const char *)svg,frame_size);
            auto bitmap = document->renderToBitmap();

            if(w==bitmap.width()&&h==bitmap.height()) {
                
                for(int i=0; i<h; i++) {
                    
                    unsigned char *dst = (unsigned char *)pixelAddress+(i*rowBytes);
                    unsigned char *src = (unsigned char *)(bitmap.data()+((h-1)-i)*bitmap.stride());
                    
                    for(int j=0; j<w; j++) {
                        
                        // BGRA
                        *dst++ = *src++;
                        *dst++ = *src++;
                        *dst++ = *src++;
                        *dst++ = *src++;
                    }
                }
            }
           
            delete[] svg;

            localRecP->PPixCacheSuite->AddFrameToCache(localRecP->importerID,0,ppix,theFrame,NULL,NULL);
            *sourceVideoRec->outFrame = ppix;
        
            // Premiere copied the frame to its cache, so we dispose ours. Very obvious memory leak if we don't.
            // localRecP->PPixSuite->Dispose(ppix);
            
        }
        else {
            assert(false); // looks like Premiere is happy to always give me this kind of buffer
        }
    }

    stdParms->piSuites->memFuncs->unlockHandle(reinterpret_cast<char**>(ldataH));

    return result;
}

PREMPLUGENTRY DllExport xImportEntry(csSDK_int32 selector, imStdParms *stdParms, void *param1, void *param2) {
    
    prMALError result = imUnsupported;

    try{
        switch (selector) {
            case imInit:
                result = SDKInit(stdParms,reinterpret_cast<imImportInfoRec*>(param1));
                break;

            case imGetInfo8:
                result = SDKGetInfo8(stdParms,reinterpret_cast<imFileAccessRec8*>(param1),reinterpret_cast<imFileInfoRec8*>(param2));
                break;

            case imOpenFile8:
                result = SDKOpenFile8(stdParms,reinterpret_cast<imFileRef*>(param1),reinterpret_cast<imFileOpenRec8*>(param2));
                break;
            
            case imQuietFile:
                result = SDKQuietFile(stdParms,reinterpret_cast<imFileRef*>(param1),param2);
                break;

            case imCloseFile:
                result = SDKCloseFile(stdParms,reinterpret_cast<imFileRef*>(param1),param2);
                break;

            case imAnalysis:
                result = SDKAnalysis(stdParms,reinterpret_cast<imFileRef>(param1),reinterpret_cast<imAnalysisRec*>(param2));
                break;

            case imGetIndFormat:
                result = SDKGetIndFormat(stdParms,reinterpret_cast<csSDK_size_t>(param1),reinterpret_cast<imIndFormatRec*>(param2));
                break;

            case imGetIndPixelFormat:
                result = SDKGetIndPixelFormat(stdParms,reinterpret_cast<csSDK_size_t>(param1),reinterpret_cast<imIndPixelFormatRec*>(param2));
                break;

            // Importers that support the Premiere Pro 2.0 API must return malSupports8 for this selector
            case imGetSupports8:
                result = malSupports8;
                break;

            case imGetPreferredFrameSize:
                result = SDKPreferredFrameSize(stdParms,reinterpret_cast<imPreferredFrameSizeRec*>(param1));
                break;

            case imGetSourceVideo:
                result = SDKGetSourceVideo(stdParms,reinterpret_cast<imFileRef>(param1),reinterpret_cast<imSourceVideoRec*>(param2));
                break;
            
            case imCreateAsyncImporter:
                result = imUnsupported;
                break;
        }
    
    }
    catch(...) { result = imOtherErr; }

    return result;
}
