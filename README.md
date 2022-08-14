# asvg

Dependency on [lunasvg](https://github.com/sammycage/lunasvg)

### Premiere Pro importers

`/Library/Application\ Support/Adobe/Common/Plug-ins/7.0/MediaCore/asvg_File_Import.bundle`

Based on  [https://github.com/fnordware/AdobeOgg/tree/theora/](https://github.com/fnordware/AdobeOgg/tree/theora/)

File Extension is `asvg`.

```
char formatname[255] = "asvg";
char shortname[32] = "asvg";
char platformXten[256] = "asvg\0";
```

```
resource 'IMPT' (1000)
{
0x61737667 // 'asvg'
};
```