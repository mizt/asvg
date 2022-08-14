#import <Foundation/Foundation.h>
#import "MultiTrackQTMovie.h"

int main(int argc, char *argv[]) {
	@autoreleasepool {
		const int W = 1920;
		const int H = 1440; 
		std::vector<MultiTrackQTMovie::TrackInfo> info;
		info.push_back({.width=W,.height=H,.depth=32,.fps=30.,.type="asvg"});
		MultiTrackQTMovie::Recorder *recorder = new MultiTrackQTMovie::Recorder(@"test.asvg",&info);		
		NSString *setting = [NSString stringWithFormat:@"<svg version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" x=\"0px\" y=\"0px\" viewBox=\"0 0 %d %d\" style=\"enable-background:new 0 0 %d %d;\" xml:space=\"preserve\"><rect x=\"0\" y=\"0\" width=\"%d\" height=\"%d\" fill=\"black\" stroke=\"none\" />",W,H,W,H,W,H];
		for(int k=0; k<30; k++) {
			NSMutableString *svg = [NSMutableString stringWithCapacity:0];
			[svg appendString:@"<?xml version=\"1.0\" encoding=\"utf-8\"?>"];
			[svg appendString:setting];
			[svg appendString:@"<g id=\"lines\" fill=\"none\" stroke=\"#FFF\">"];
			[svg appendString:[NSString stringWithFormat:@"<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\"/>",
				(int)(random()%W),
				(int)(random()%H),
				(int)(random()%W),
				(int)(random()%H)
			]];
			[svg appendString:@"</g></svg>"];
			NSData *data = [svg dataUsingEncoding:NSUTF8StringEncoding];
			recorder->add((unsigned char *)[data bytes],(unsigned int)[data length],0,false);
		}
		recorder->save();
	}
}