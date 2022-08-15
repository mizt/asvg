#import "Emscripten.h"
#import "MultiTrackQTMovieParser.h"

EM_JS(void,set,(const char *message), {
	const img = document.getElementById("svg"); 
	img.src = UTF8ToString(message);
});

namespace Info {
	unsigned int width = 0;
	unsigned int height = 0;
	unsigned int length = 0;
	unsigned int frame = 0;
}

extern "C" {
	
	const unsigned int TRACK_ID = 0;
	MultiTrackQTMovie::Parser *parser = nullptr;

	
	EMSCRIPTEN_KEEPALIVE unsigned int width() {
		return Info::width;
	}
	
	EMSCRIPTEN_KEEPALIVE unsigned int height() {
		return Info::height;
	}
	
	EMSCRIPTEN_KEEPALIVE unsigned int length() {
		return Info::length;
	}
	
	EMSCRIPTEN_KEEPALIVE void setup(unsigned char *data, int length) {
		
		if(parser!=nullptr) {
			
			delete[] parser;
			
			Info::width = 0;
			Info::height = 0;
			Info::length = 0;
		}
		
		parser = new MultiTrackQTMovie::Parser(data,length);
		
		if(parser) {
			Info::width = parser->width(TRACK_ID);
			Info::height = parser->height(TRACK_ID);
			Info::length = parser->length(TRACK_ID);
		}
	}
	
	EMSCRIPTEN_KEEPALIVE void update() {
		
		if(parser) {
			
			unsigned long long offset = 0;
			unsigned int size = 0;
			
			if(parser->get(Info::frame,TRACK_ID,&offset,&size)) {
				std::string str((const char *)(parser->bytes()+offset),size);
				set(str.c_str());
			}
			
			Info::frame++;
			if(Info::frame>Info::length) Info::frame = 0;
		}
	}
}

