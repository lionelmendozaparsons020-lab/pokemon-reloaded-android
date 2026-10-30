#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
int gm_ios_run(void *view,uint32_t w,uint32_t h,const char *root,const char *font,bool smoke);
int gm_ios_import(const char *zip,const char *destination);
int gm_ios_saves(const char *root,const char *file,uint32_t slot,bool importing);
bool gm_ios_has_game(const char *root);
void gm_ios_error(char *out,size_t size);
void gm_ios_key(uint32_t code,bool down);
void gm_ios_text(uint32_t ch);
void gm_ios_pointer(uint32_t kind,float x,float y,bool right);
void gm_ios_release_all(void);
void gm_ios_set_active(bool active);
void gm_ios_close(void);
void gm_ios_resize(uint16_t w,uint16_t h);
void gm_ios_audio_fill(float *out,uint32_t frames);

void gm_ios_configure(const char *documents);
void gm_ios_touch(uint32_t kind,int32_t id,float x,float y);
void gm_ios_pump(void);
void gm_ios_tap(uint32_t code);
void gm_ios_ime_inset(uint32_t pixels);

void gm_ios_layout_json(uint8_t context,float w,float h,char *out,size_t size);
