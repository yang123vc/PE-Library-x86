;==============================================================================
;
; PE LIBRARY
;
; Copyright (c) 2019 by fearless
;
; All Rights Reserved
;
; http://www.LetTheLight.in
;
; http://github.com/mrfearless
;
;
; This software is provided 'as-is', without any express or implied warranty.
; In no event will the author be held liable for any damages arising from the
; use of this software.
;
; Permission is granted to anyone to use this software for any non-commercial
; program. If you use the library in an application, an acknowledgement in the
; application or documentation is appreciated but not required.
;
; You are allowed to make modifications to the source code, but you must leave
; the original copyright notices intact and not misrepresent the origin of the
; software. It is not allowed to claim you wrote the original software.
; Modified files must have a clear notice that the files are modified, and not
; in the original state. This includes the name of the person(s) who modified
; the code.
;
; If you want to distribute or redistribute any portion of this package, you
; will need to include the full package in it's original state, including this
; license and all the copyrights.
;
; While distributing this package (in it's original state) is allowed, it is
; not allowed to charge anything for this. You may not sell or include the
; package in any commercial package without having permission of the author.
; Neither is it allowed to redistribute any of the package's components with
; commercial applications.
;
;==============================================================================
.686
.MMX
.XMM
.model flat,stdcall
option casemap:none
include \masm32\macros\macros.asm

;DEBUG32 EQU 1
;IFDEF DEBUG32
;    PRESERVEXMMREGS equ 1
;    includelib M:\Masm32\lib\Debug32.lib
;    DBG32LIB equ 1
;    DEBUGEXE textequ <'M:\Masm32\DbgWin.exe'>
;    include M:\Masm32\include\debug32.inc
;ENDIF

include windows.inc

include user32.inc
includelib user32.lib

include kernel32.inc
includelib kernel32.lib

include PE.inc

;-------------------------------------------------------------------------
; Prototypes for internal use
;-------------------------------------------------------------------------
PESignature             PROTO :DWORD
PEJustFname             PROTO :DWORD, :DWORD

PEIncreaseFileSize      PROTO :DWORD, :DWORD
PEDecreaseFileSize      PROTO :DWORD, :DWORD

PE_SetError             PROTO :DWORD, :DWORD

PUBLIC PELIB_ErrorNo

;-------------------------------------------------------------------------
; Structures for internal use
;-------------------------------------------------------------------------

IFNDEF PEINFO
PEINFO                      STRUCT
    PEOpenMode              DD 0
    PEHandle                DD 0
    PEFilename              DB MAX_PATH DUP (0)
    PEFilesize              DD 0
    PEVersion               DD 0
    PE64                    DD 0
    PEDLL                   DD 0
    PEDOSHeader             DD 0
    PENTHeader              DD 0
    PEFileHeader            DD 0
    PEOptionalHeader        DD 0
    PESectionTable          DD 0
    PESectionCount          DD 0
    PEOptionalHeaderSize    DD 0
    PEImageBase             DD 0
    PE64ImageBase           DQ 0
    PENumberOfRvaAndSizes   DD 0
    PEDataDirectories       DD 0
    PEExportCount           DD 0
    PEExportDirectoryTable  DD 0
    PEExportAddressTable    DD 0
    PEExportNamePointerTable DD 0
    PEExportOrdinalTable    DD 0
    PEExportNameTable       DD 0
    PEImportDirectoryCount  DD 0
    PEImportDirectoryTable  DD 0
    PEImportLookupTable     DD 0
    PEImportNameTable       DD 0
    PEImportAddressTable    DD 0
    PEResourceDirectoryTable DD 0
    PEResourceDirectoryEntries DD 0
    PEResourceDirectoryString DD 0
    PEResourceDataEntry     DD 0
    PEExceptionTable        DD 0
    PECertificateTable      DD 0
    PEBaseRelocationTable   DD 0
    PEDebugData             DD 0
    PEGlobalPtr             DD 0
    PETLSTable              DD 0
    PELoadConfigTable       DD 0
    PEBoundImportTable      DD 0
    PEDelayImportDescriptor DD 0
    PECLRRuntimeHeader      DD 0
    PEMemMapPtr             DD 0
    PEMemMapHandle          DD 0
    PEFileHandle            DD 0
PEINFO                      ENDS
ENDIF

.CONST



.DATA
PELIB_ErrorNo               DD PE_ERROR_NO_HANDLE ; Global to store error no


.CODE
PE_ALIGN
;------------------------------------------------------------------------------
; PE_OpenFile - Opens a PE file (exe/dll/ocx/cpl etc)
; Returns: TRUE or FALSE. If TRUE a PE handle (hPE) is stored in the variable
; pointed to by lpdwPEHandle. If FALSE, use PE_GetError to get further info.
;
; Note: Calls PE_Analyze to process the PE file. Use PE_CloseFile when finished
;------------------------------------------------------------------------------
PE_OpenFile PROC USES EBX lpszPEFilename:DWORD, bReadOnly:DWORD, lpdwPEHandle:DWORD
    LOCAL hPE:DWORD
    LOCAL hPEFile:DWORD
    LOCAL PEMemMapHandle:DWORD
    LOCAL PEMemMapPtr:DWORD
    LOCAL PEFilesize:DWORD
    LOCAL PEVersion:DWORD
    
    IFDEF DEBUG32
    PrintText 'PE_OpenFile'
    ENDIF
    
    .IF lpdwPEHandle == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    
    .IF lpszPEFilename == NULL
        Invoke PE_SetError, NULL, PE_ERROR_OPEN_FILE
        mov ebx, lpdwPEHandle
        mov eax, 0
        mov [ebx], eax
        xor eax, eax
        ret
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Open file for read only or read/write access
    ;--------------------------------------------------------------------------
    .IF bReadOnly == TRUE
        Invoke CreateFile, lpszPEFilename, GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL
    .ELSE
        Invoke CreateFile, lpszPEFilename, GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL
    .ENDIF
    .IF eax == INVALID_HANDLE_VALUE
        Invoke PE_SetError, NULL, PE_ERROR_OPEN_FILE
        mov ebx, lpdwPEHandle
        mov eax, 0
        mov [ebx], eax
        xor eax, eax
        ret
    .ENDIF
    mov hPEFile, eax ; store file handle
    
    ;--------------------------------------------------------------------------
    ; Get file size and verify its not too low or too high in size
    ;--------------------------------------------------------------------------
    Invoke GetFileSize, hPEFile, NULL
    .IF eax < 268d ; https://www.bigmessowires.com/2015/10/08/a-handmade-executable-file/
        Invoke CloseHandle, hPEFile
        Invoke PE_SetError, NULL, PE_ERROR_OPEN_SIZE_LOW
        mov ebx, lpdwPEHandle
        mov eax, 0
        mov [ebx], eax
        xor eax, eax
        ret
    .ELSEIF eax > 1FFFFFFFh ; 536,870,911 536MB+ - rare to be this size or larger
        Invoke CloseHandle, hPEFile
        Invoke PE_SetError, NULL, PE_ERROR_OPEN_SIZE_HIGH
        mov ebx, lpdwPEHandle
        mov eax, 0
        mov [ebx], eax
        xor eax, eax
        ret    
    .ENDIF
    mov PEFilesize, eax ; file size

    ;--------------------------------------------------------------------------
    ; Create file mapping of entire file
    ;--------------------------------------------------------------------------
    .IF bReadOnly == TRUE
        Invoke CreateFileMapping, hPEFile, NULL, PAGE_READONLY, 0, 0, NULL ; Create memory mapped file
    .ELSE
        Invoke CreateFileMapping, hPEFile, NULL, PAGE_READWRITE, 0, 0, NULL ; Create memory mapped file
    .ENDIF
    .IF eax == NULL
        Invoke CloseHandle, hPEFile
        Invoke PE_SetError, NULL, PE_ERROR_OPEN_MAP
        mov ebx, lpdwPEHandle
        mov eax, 0
        mov [ebx], eax
        xor eax, eax
        ret
    .ENDIF
    mov PEMemMapHandle, eax ; store mapping handle
    
    ;--------------------------------------------------------------------------
    ; Create view of file
    ;--------------------------------------------------------------------------
    .IF bReadOnly == TRUE
        Invoke MapViewOfFileEx, PEMemMapHandle, FILE_MAP_READ, 0, 0, 0, NULL
    .ELSE
        Invoke MapViewOfFileEx, PEMemMapHandle, FILE_MAP_ALL_ACCESS, 0, 0, 0, NULL
    .ENDIF    
    .IF eax == NULL
        Invoke CloseHandle, PEMemMapHandle
        Invoke CloseHandle, hPEFile
        Invoke PE_SetError, NULL, PE_ERROR_OPEN_VIEW
        mov ebx, lpdwPEHandle
        mov eax, 0
        mov [ebx], eax
        xor eax, eax
        ret
    .ENDIF
    mov PEMemMapPtr, eax ; store map view pointer

    ;--------------------------------------------------------------------------
    ; Check PE file signature - to make sure MZ and PE sigs are located
    ;--------------------------------------------------------------------------
    Invoke PESignature, PEMemMapPtr
    .IF eax == PE_INVALID
        ;----------------------------------------------------------------------
        ; Invalid PE file, so close all handles and return error
        ;----------------------------------------------------------------------
        Invoke UnmapViewOfFile, PEMemMapPtr
        Invoke CloseHandle, PEMemMapHandle
        Invoke CloseHandle, hPEFile
        Invoke PE_SetError, NULL, PE_ERROR_OPEN_INVALID
        mov ebx, lpdwPEHandle
        mov eax, 0
        mov [ebx], eax
        xor eax, eax
        ret
    .ELSE ; eax == PE_ARCH_32 || eax == PE_ARCH_64
        ;----------------------------------------------------------------------
        ; PE file is valid. So we process PE file and get pointers and other 
        ; information and store in a 'handle' (hPE) that we return. 
        ; Handle is a pointer to a PEINFO struct that stores PE file info.
        ;----------------------------------------------------------------------
        Invoke PE_Analyze, PEMemMapPtr, lpdwPEHandle
        .IF eax == FALSE
            ;------------------------------------------------------------------
            ; Error processing PE file, so close all handles and return error
            ;------------------------------------------------------------------        
            Invoke UnmapViewOfFile, PEMemMapPtr
            Invoke CloseHandle, PEMemMapHandle
            Invoke CloseHandle, hPEFile
            xor eax, eax
            ret
        .ENDIF
    .ENDIF
    
    ;--------------------------------------------------------------------------
    ; Success in processing PE file. Store additional information like file and
    ; map handles and filesize in our PEINFO struct (hPE) if we reach here.
    ;--------------------------------------------------------------------------
    .IF lpdwPEHandle == NULL
        Invoke UnmapViewOfFile, PEMemMapPtr
        Invoke CloseHandle, PEMemMapHandle
        Invoke CloseHandle, hPEFile
        Invoke PE_SetError, NULL, PE_ERROR_OPEN_INVALID    
        mov ebx, lpdwPEHandle
        mov eax, 0
        mov [ebx], eax
        xor eax, eax
        ret
    .ENDIF       
    
    mov ebx, lpdwPEHandle
    mov eax, [ebx]
    mov hPE, eax
    mov ebx, hPE
    mov eax, lpdwPEHandle
    mov [ebx].PEINFO.PEHandle, eax
    mov eax, bReadOnly
    mov [ebx].PEINFO.PEOpenMode, eax        
    mov eax, PEMemMapHandle
    mov [ebx].PEINFO.PEMemMapHandle, eax
    mov eax, hPEFile
    mov [ebx].PEINFO.PEFileHandle, eax
    mov eax, PEFilesize
    mov [ebx].PEINFO.PEFilesize, eax
    .IF lpszPEFilename != NULL
        lea eax, [ebx].PEINFO.PEFilename
        Invoke lstrcpyn, eax, lpszPEFilename, MAX_PATH
    .ENDIF        
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    mov ebx, lpdwPEHandle
    mov eax, hPE
    mov [ebx], eax
    
    ;mov eax, hPE ; Return handle for our user to store and use in other functions
    mov eax, TRUE
    ret
PE_OpenFile ENDP

PE_ALIGN
;------------------------------------------------------------------------------
; PE_CloseFile - Close PE File
; Returns: None
;------------------------------------------------------------------------------
PE_CloseFile PROC USES EBX hPE:DWORD

    IFDEF DEBUG32
    PrintText 'PE_CloseFile'
    ENDIF
    
    .IF hPE == NULL
        xor eax, eax
        ret
    .ENDIF

    mov ebx, hPE
    mov ebx, [ebx].PEINFO.PEHandle
    .IF ebx != 0
        mov eax, 0 ; null out hPE handle if it exists
        mov [ebx], eax
    .ENDIF

    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEMemMapPtr
    .IF eax != NULL
        Invoke UnmapViewOfFile, eax
    .ENDIF

    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEMemMapHandle
    .IF eax != NULL
        Invoke CloseHandle, eax
    .ENDIF

    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEFileHandle
    .IF eax != NULL
        Invoke CloseHandle, eax
    .ENDIF

    mov eax, hPE
    .IF eax != NULL
        Invoke GlobalFree, eax
    .ENDIF
    
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    xor eax, eax
    ret
PE_CloseFile ENDP

PE_ALIGN
;------------------------------------------------------------------------------
; PE_Analyze - Process memory mapped PE file 
; Returns: TRUE or FALSE. If TRUE a PE handle (hPE) is stored in the variable
; pointed to by lpdwPEHandle. If FALSE, use PE_GetError to get further info.
;
; Can be used directly on memory region where PE is already loaded/mapped
;
; PE_Analyze is also called by PE_OpenFile.
; Note: Use PE_Finish when finished with PE file if using PE_Analyze directly.
;------------------------------------------------------------------------------
PE_Analyze PROC USES EBX EDX pPEInMemory:DWORD, lpdwPEHandle:DWORD
    LOCAL hPE:DWORD
    LOCAL PEMemMapPtr:DWORD
    LOCAL pFileHeader:DWORD
    LOCAL pOptionalHeader:DWORD
    LOCAL pDataDirectories:DWORD
    LOCAL pSectionTable:DWORD
    LOCAL pImportDirectoryTable:DWORD
    LOCAL pCurrentSection:DWORD
    LOCAL dwNumberOfSections:DWORD
    LOCAL dwSizeOfOptionalHeader:DWORD
    LOCAL dwNumberOfRvaAndSizes:DWORD
    LOCAL dwCurrentSection:DWORD
    LOCAL bPE64:DWORD
    
    IFDEF DEBUG32
    PrintText 'PE_Analyze'
    ENDIF    
    
    .IF lpdwPEHandle == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF    
    
    .IF pPEInMemory == NULL
        Invoke PE_SetError, NULL, PE_ERROR_ANALYZE_NULL
        mov ebx, lpdwPEHandle
        mov eax, 0
        mov [ebx], eax
        xor eax, eax
        ret
    .ENDIF
    
    mov eax, pPEInMemory
    mov PEMemMapPtr, eax       
    
    ;--------------------------------------------------------------------------
    ; Alloc mem for our PE Handle (PEINFO)
    ;--------------------------------------------------------------------------
    Invoke GlobalAlloc, GMEM_FIXED or GMEM_ZEROINIT, SIZEOF PEINFO
    .IF eax == NULL
        Invoke PE_SetError, NULL, PE_ERROR_ANALYZE_ALLOC
        mov ebx, lpdwPEHandle
        mov eax, 0
        mov [ebx], eax
        xor eax, eax
        ret
    .ENDIF
    mov hPE, eax
    
    mov edx, hPE
    mov eax, PEMemMapPtr
    mov [edx].PEINFO.PEMemMapPtr, eax
    mov [edx].PEINFO.PEDOSHeader, eax

    ; Process PE in memory
    mov eax, PEMemMapPtr
    mov ebx, eax ; ebx points to IMAGE_DOS_HEADER in memory
    .IF [ebx].IMAGE_DOS_HEADER.e_lfanew == 0
        Invoke PE_SetError, hPE, PE_ERROR_ANALYZE_INVALID
        .IF hPE != NULL
            Invoke GlobalFree, hPE
        .ENDIF
        mov ebx, lpdwPEHandle
        mov eax, 0
        mov [ebx], eax
        xor eax, eax
        ret
    .ENDIF    
    
    ;--------------------------------------------------------------------------
    ; Get headers: NT, File, Optional & other useful fields
    ;--------------------------------------------------------------------------
    ; ebx points to IMAGE_DOS_HEADER in memory
    add eax, [ebx].IMAGE_DOS_HEADER.e_lfanew
    mov [edx].PEINFO.PENTHeader, eax
    mov ebx, eax ; ebx points to IMAGE_NT_HEADERS
    lea eax, [ebx].IMAGE_NT_HEADERS.FileHeader
    mov [edx].PEINFO.PEFileHeader, eax
    mov pFileHeader, eax
    lea eax, [ebx].IMAGE_NT_HEADERS.OptionalHeader
    mov [edx].PEINFO.PEOptionalHeader, eax
    mov pOptionalHeader, eax
    mov ebx, pFileHeader ; ebx points to IMAGE_FILE_HEADER
    movzx eax, word ptr [ebx].IMAGE_FILE_HEADER.NumberOfSections
    mov [edx].PEINFO.PESectionCount, eax
    mov dwNumberOfSections, eax
    movzx eax, word ptr [ebx].IMAGE_FILE_HEADER.SizeOfOptionalHeader
    mov [edx].PEINFO.PEOptionalHeaderSize, eax
    mov dwSizeOfOptionalHeader, eax
    movzx eax, word ptr [ebx].IMAGE_FILE_HEADER.Characteristics
    and eax, IMAGE_FILE_DLL
    .IF eax == IMAGE_FILE_DLL
        mov [edx].PEINFO.PEDLL, TRUE
    .ELSE
        mov [edx].PEINFO.PEDLL, FALSE
    .ENDIF        
    
    .IF dwSizeOfOptionalHeader == 0
        mov pOptionalHeader, 0
        mov pDataDirectories, 0
        mov dwNumberOfRvaAndSizes, 0
        mov bPE64, FALSE
    .ELSE
        ;----------------------------------------------------------------------
        ; Get PE32/PE32+ magic number
        ;----------------------------------------------------------------------
        mov ebx, pOptionalHeader; ebx points to IMAGE_OPTIONAL_HEADER
        movzx eax, word ptr [ebx]
        .IF eax == IMAGE_NT_OPTIONAL_HDR32_MAGIC ; PE32
            mov ebx, hPE
            mov [edx].PEINFO.PE64, FALSE
            mov bPE64, FALSE
        .ELSEIF eax == IMAGE_NT_OPTIONAL_HDR64_MAGIC ; PE32+ (PE64)
            mov ebx, hPE
            mov [edx].PEINFO.PE64, TRUE
            mov bPE64, TRUE
        .ELSE ; ROM or something else
            Invoke PE_SetError, hPE, PE_ERROR_ANALYZE_INVALID
            .IF hPE != NULL
                Invoke GlobalFree, hPE
            .ENDIF
            mov ebx, lpdwPEHandle
            mov eax, 0
            mov [ebx], eax
            xor eax, eax
            ret
        .ENDIF
        
        mov eax, dwSizeOfOptionalHeader
        .IF eax == 28 || eax == 24
            ;------------------------------------------------------------------
            ; Standard fields in IMAGE_OPTIONAL_HEADER
            ;------------------------------------------------------------------
            mov pDataDirectories, 0
            mov dwNumberOfRvaAndSizes, 0
        .ELSEIF eax == 68 || eax == 88 ; Windows specific fields in IMAGE_OPTIONAL_HEADER
            ;------------------------------------------------------------------
            ; Windows specific fields in IMAGE_OPTIONAL_HEADER
            ; Get ImageBase, Subsystem, DllCharacteristics
            ;------------------------------------------------------------------
            mov pDataDirectories, 0
            mov dwNumberOfRvaAndSizes, 0
            mov ebx, pOptionalHeader ; ebx points to IMAGE_OPTIONAL_HEADER
            .IF bPE64 == TRUE ; ebx points to IMAGE_OPTIONAL_HEADER64
                mov eax, dword ptr [ebx].IMAGE_OPTIONAL_HEADER64.ImageBase
                mov dword ptr [edx].PEINFO.PE64ImageBase, eax
                mov eax, dword ptr [ebx+4].IMAGE_OPTIONAL_HEADER64.ImageBase
                mov dword ptr [edx+4].PEINFO.PE64ImageBase, eax 
                mov [edx].PEINFO.PEImageBase, 0
             .ELSE ; ebx points to IMAGE_OPTIONAL_HEADER32
                mov eax, [ebx].IMAGE_OPTIONAL_HEADER32.ImageBase
                mov [edx].PEINFO.PEImageBase, eax
            .ENDIF
        .ELSE
            ;------------------------------------------------------------------
            ; Data Directories in IMAGE_OPTIONAL_HEADER
            ;------------------------------------------------------------------
            mov ebx, pOptionalHeader ; ebx points to IMAGE_OPTIONAL_HEADER
            .IF bPE64 == TRUE ; ebx points to IMAGE_OPTIONAL_HEADER64
                mov eax, dword ptr [ebx].IMAGE_OPTIONAL_HEADER64.ImageBase
                mov dword ptr [edx].PEINFO.PE64ImageBase, eax
                mov eax, dword ptr [ebx+4].IMAGE_OPTIONAL_HEADER64.ImageBase
                mov dword ptr [edx+4].PEINFO.PE64ImageBase, eax 
                mov [edx].PEINFO.PEImageBase, 0
                mov eax, [ebx].IMAGE_OPTIONAL_HEADER64.NumberOfRvaAndSizes
                mov [edx].PEINFO.PENumberOfRvaAndSizes, eax
                mov dwNumberOfRvaAndSizes, eax
                mov ebx, pOptionalHeader
                add ebx, SIZEOF_STANDARD_FIELDS_PE64
                add ebx, SIZEOF_WINDOWS_FIELDS_PE64                    
                mov pDataDirectories, ebx
            .ELSE ; ebx points to IMAGE_OPTIONAL_HEADER32
                mov eax, [ebx].IMAGE_OPTIONAL_HEADER32.ImageBase
                mov [edx].PEINFO.PEImageBase, eax
                mov eax, [ebx].IMAGE_OPTIONAL_HEADER32.NumberOfRvaAndSizes
                mov [edx].PEINFO.PENumberOfRvaAndSizes, eax
                mov dwNumberOfRvaAndSizes, eax
                mov ebx, pOptionalHeader
                add ebx, SIZEOF_STANDARD_FIELDS_PE32
                add ebx, SIZEOF_WINDOWS_FIELDS_PE32
                mov pDataDirectories, ebx
            .ENDIF                
        .ENDIF
    .ENDIF
    
    ;--------------------------------------------------------------------------
    ; Get pointer to SectionTable
    ;--------------------------------------------------------------------------
    mov eax, pFileHeader
    add eax, SIZEOF IMAGE_FILE_HEADER
    add eax, dwSizeOfOptionalHeader
    mov [edx].PEINFO.PESectionTable, eax
    mov pSectionTable, eax
    mov pCurrentSection, eax
    
    mov dwCurrentSection, 0
    mov eax, 0
    .WHILE eax < dwNumberOfSections
        mov ebx, pCurrentSection
        ; do stuff with sections
        ; PointerToRawData to get section data
        add pCurrentSection, SIZEOF IMAGE_SECTION_HEADER
        inc dwCurrentSection
        mov eax, dwCurrentSection
    .ENDW
    
    ;--------------------------------------------------------------------------
    ; Get Data Directories
    ;--------------------------------------------------------------------------
    IFDEF DEBUG32
    mov eax, dwNumberOfRvaAndSizes
    mov ebx, SIZEOF IMAGE_DATA_DIRECTORY
    mul ebx
    DbgDump pDataDirectories, eax
    ENDIF
    
    mov pImportDirectoryTable, 0
    
    .IF pDataDirectories != 0
        mov edx, hPE
        .IF dwNumberOfRvaAndSizes > 0 ; Export Table
            mov ebx, pDataDirectories
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PEExportDirectoryTable, eax
            .ENDIF
        .ENDIF
        .IF dwNumberOfRvaAndSizes > 1 ; Import Table
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PEImportDirectoryTable, eax
                mov pImportDirectoryTable, eax
            .ENDIF
        .ENDIF
        .IF dwNumberOfRvaAndSizes > 2 ; Resource Table
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PEResourceDirectoryTable, eax
            .ENDIF
        .ENDIF            
        .IF dwNumberOfRvaAndSizes > 3 ; Exception Table
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PEExceptionTable, eax
            .ENDIF
        .ENDIF
        .IF dwNumberOfRvaAndSizes > 4 ; Certificate Table
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PECertificateTable, eax
            .ENDIF
        .ENDIF
        .IF dwNumberOfRvaAndSizes > 5 ; Base Relocation Table
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PEBaseRelocationTable, eax
            .ENDIF
        .ENDIF
        .IF dwNumberOfRvaAndSizes > 6 ; Debug Data
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PEDebugData, eax
            .ENDIF
        .ENDIF
        ;.IF dwNumberOfRvaAndSizes > 7 ; Data Directory Architecture
            ;mov ebx, pDataDirectories
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            ;.IF eax != 0
            ;    add eax, PEMemMapPtr
            ;    mov pDataDirArchitecture, eax
            ;.ENDIF
        ;.ENDIF
        .IF dwNumberOfRvaAndSizes > 8 ; Global Ptr
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PEGlobalPtr, eax
            .ENDIF
        .ENDIF
        .IF dwNumberOfRvaAndSizes > 9 ; TLS Table
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PETLSTable, eax
            .ENDIF
        .ENDIF
        .IF dwNumberOfRvaAndSizes > 10 ; Load Config Table
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PELoadConfigTable, eax
            .ENDIF
        .ENDIF
        .IF dwNumberOfRvaAndSizes > 11 ; Bound Import Table
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PEBoundImportTable, eax
            .ENDIF
        .ENDIF
        .IF dwNumberOfRvaAndSizes > 12 ; Import Address Table
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PEImportAddressTable, eax
            .ENDIF
        .ENDIF
        .IF dwNumberOfRvaAndSizes > 13 ; Delay Import Descriptor
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PEDelayImportDescriptor, eax
            .ENDIF
        .ENDIF
        .IF dwNumberOfRvaAndSizes > 14 ; CLR Runtime Header
            mov ebx, pDataDirectories
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            .IF eax != 0
                add eax, PEMemMapPtr
                mov [edx].PEINFO.PECLRRuntimeHeader, eax
            .ENDIF
        .ENDIF
        ;.IF dwNumberOfRvaAndSizes > 15 ; DataDir Reserved
            ;mov ebx, pDataDirectories
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;add ebx, SIZEOF IMAGE_DATA_DIRECTORY
            ;mov eax, [ebx].IMAGE_DATA_DIRECTORY.VirtualAddress
            ;.IF eax != 0
            ;    add eax, PEMemMapPtr
            ;    mov pDataDirReserved, eax
            ;.ENDIF
        ;.ENDIF
    .ENDIF
    
    ;--------------------------------------------------------------------------
    ; Import 
    ;--------------------------------------------------------------------------
    .IF pImportDirectoryTable != 0
        mov eax, 0
        mov ebx, pImportDirectoryTable
        .WHILE [ebx].IMAGE_IMPORT_DESCRIPTOR.Characteristics != 0
            inc eax
            add ebx, SIZEOF IMAGE_IMPORT_DESCRIPTOR
        .ENDW
        mov edx, hPE
        mov [edx].PEINFO.PEImportDirectoryCount, eax 

    .ENDIF
    
    
    
    
    IFDEF DEBUG32
    mov eax, dwNumberOfSections
    mov ebx, SIZEOF IMAGE_SECTION_HEADER
    mul ebx
    DbgDump pSectionTable, eax    
    ENDIF

    ;--------------------------------------------------------------------------
    ; Update PEINFO handle information
    ;--------------------------------------------------------------------------
    mov edx, hPE
    mov eax, lpdwPEHandle
    mov [edx].PEINFO.PEHandle, eax

    mov ebx, lpdwPEHandle
    mov eax, hPE
    mov [ebx], eax

    mov eax, TRUE
    ret
PE_Analyze ENDP

PE_ALIGN
;------------------------------------------------------------------------------
; PE_Finish - Frees up hPE if PE was processed from memory directly with a call
; to PE_Analyze. If PE was opened as a file via PE_OpenFile, then PE_CloseFile 
; should be used instead of this function.
; Returns: None
;------------------------------------------------------------------------------
PE_Finish PROC USES EBX hPE:DWORD

    IFDEF DEBUG32
    PrintText 'PE_Finish'
    ENDIF
    
    .IF hPE == NULL
        xor eax, eax
        ret
    .ENDIF
    
    mov ebx, hPE
    mov ebx, [ebx].PEINFO.PEHandle
    .IF ebx != 0
        mov eax, 0 ; null out hPE handle if it exists
        mov [ebx], eax
    .ENDIF
        
    mov eax, hPE
    .IF eax != NULL
        Invoke GlobalFree, eax
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    xor eax, eax
    ret
PE_Finish ENDP




;############################################################################
;  H E A D E R   F U N C T I O N S
;############################################################################

PE_ALIGN
;----------------------------------------------------------------------------
; PE_HeaderDOS - returns pointer to IMAGE_DOS_HEADER of PE file
;----------------------------------------------------------------------------
PE_HeaderDOS PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEDOSHeader
    ; eax points to IMAGE_DOS_HEADER
    ret
PE_HeaderDOS ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_HeaderNT - returns pointer to IMAGE_NT_HEADERS of PE file
;----------------------------------------------------------------------------
PE_HeaderNT PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PENTHeader
    ; eax points to IMAGE_NT_HEADERS
    ret
PE_HeaderNT ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_HeaderFile - return pointer to IMAGE_FILE_HEADER of PE file
;----------------------------------------------------------------------------
PE_HeaderFile PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEFileHeader
    ; eax points to IMAGE_FILE_HEADER
    ret
PE_HeaderFile ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_HeaderOptional - returns pointer to IMAGE_OPTIONAL_HEADER (32/64)
;----------------------------------------------------------------------------
PE_HeaderOptional PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEOptionalHeader
    ; eax points to IMAGE_OPTIONAL_HEADER (32/64)
    ret
PE_HeaderOptional ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_HeaderSections - returns pointer to array of IMAGE_SECTION_HEADER
;----------------------------------------------------------------------------
PE_HeaderSections PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PESectionTable
    ; eax points to array of IMAGE_SECTION_HEADER entries
    ret
PE_HeaderSections ENDP




;############################################################################
;  S E C T I O N   F U N C T I O N S
;############################################################################

PE_ALIGN
;----------------------------------------------------------------------------
; PE_SectionsHeaders - returns pointer to array of IMAGE_SECTION_HEADER
;----------------------------------------------------------------------------
PE_SectionsHeaders PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PESectionTable
    ; eax points to array of IMAGE_SECTION_HEADER entries
    ret
PE_SectionsHeaders ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_SectionHeaderCount - returns no of sections
;----------------------------------------------------------------------------
PE_SectionHeaderCount PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PESectionCount
    ret
PE_SectionHeaderCount ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_SectionHeaderByIndex - Get section specified by dwSectionIndex
; Returns: pointer to section or NULL
;----------------------------------------------------------------------------
PE_SectionHeaderByIndex PROC USES EBX hPE:DWORD, dwSectionIndex:DWORD
    LOCAL pHeaderSections:DWORD
    
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF    
    
    .IF dwSectionIndex > 96d ; max sections allowed as per MS COFF docs
        xor eax, eax
        ret
    .ENDIF
    
    Invoke PE_SectionHeaderCount, hPE
    .IF dwSectionIndex >= eax
        xor eax, eax
        ret
    .ENDIF    
    
    Invoke PE_HeaderSections, hPE
    .IF eax == 0
        ret
    .ENDIF
    mov pHeaderSections, eax
    
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    mov eax, dwSectionIndex
    mov ebx, SIZEOF IMAGE_SECTION_HEADER
    mul ebx
    add eax, pHeaderSections

    ret
PE_SectionHeaderByIndex ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_SectionHeaderByName - Get section specified by lpszSectionName
; Returns: pointer to section or NULL
;----------------------------------------------------------------------------
PE_SectionHeaderByName PROC USES EBX hPE:DWORD, lpszSectionName:DWORD
    LOCAL pHeaderSections:DWORD
    LOCAL pCurrentSection:DWORD
    LOCAL nSections:DWORD
    LOCAL nSection:DWORD
    
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    
    .IF lpszSectionName == NULL
        xor eax, eax
        ret
    .ENDIF
    
    Invoke PE_HeaderSections, hPE
    .IF eax == 0
        ret
    .ENDIF
    mov pHeaderSections, eax
    
    Invoke PE_SectionHeaderCount, hPE
    mov ebx, pCurrentSection
    mov nSections, eax
    mov nSection, 0
    mov eax, 0
    .WHILE eax < nSection    
        .IF [ebx].IMAGE_SECTION_HEADER.Name1 != 0
            lea ebx, [ebx].IMAGE_SECTION_HEADER.Name1
            Invoke lstrcmp, ebx, lpszSectionName
            .IF eax == 0 ; match
                Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
                mov eax, pCurrentSection
                ret
            .ENDIF
        .ENDIF
        add pCurrentSection, SIZEOF IMAGE_SECTION_HEADER
        mov ebx, pCurrentSection
        inc nSection
        mov eax, nSection
    .ENDW
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    xor eax, eax
    ret
PE_SectionHeaderByName ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_SectionHeaderByType - Get section specified by dwSectionType
; Returns: pointer to section or NULL
;----------------------------------------------------------------------------
PE_SectionHeaderByType PROC USES EBX hPE:DWORD, dwSectionType:DWORD
    LOCAL pHeaderSections:DWORD
    LOCAL pCurrentSection:DWORD
    LOCAL nSections:DWORD
    LOCAL nSection:DWORD
    
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF    
    
    .IF dwSectionType > SEC_LAST
        xor eax, eax
        ret
    .ENDIF
    
    Invoke PE_HeaderSections, hPE
    .IF eax == 0
        ret
    .ENDIF
    mov pHeaderSections, eax
    mov pCurrentSection, eax

    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS

    Invoke PE_SectionHeaderCount, hPE
    mov ebx, pCurrentSection
    mov nSections, eax
    mov nSection, 0
    mov eax, 0
    .WHILE eax < nSections
        .IF [ebx].IMAGE_SECTION_HEADER.Name1 != 0
            lea ebx, [ebx].IMAGE_SECTION_HEADER.Name1
            mov ebx, [ebx]
            mov eax, dwSectionType
            .IF eax == SEC_BSS
                .IF ebx == 'ssb.' ; .bss
                    mov eax, pCurrentSection
                    ret
                .ENDIF
            .ELSEIF eax == SEC_CORMETA
                .IF ebx == 'roc.' ; .cormeta
                    mov eax, pCurrentSection
                    ret
                .ENDIF  
            .ELSEIF eax == SEC_DATA
                .IF ebx == 'tad.' ; .data
                    mov eax, pCurrentSection
                    ret
                .ENDIF
            .ELSEIF eax == SEC_DEBUG
                .IF ebx == 'bed.' ; .debug
                    mov eax, pCurrentSection
                    ret
                .ENDIF                  
            .ELSEIF eax == SEC_DRECTVE
                .IF ebx == 'erd.' ; .drectve
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_EDATA
                .IF ebx == 'ade.' ; .edata
                    mov eax, pCurrentSection
                    ret
                .ENDIF            
            .ELSEIF eax == SEC_IDATA
                .IF ebx == 'adi.' ; .idata
                    mov eax, pCurrentSection
                    ret
                .ENDIF            
            .ELSEIF eax == SEC_IDLSYM
                .IF ebx == 'ldi.' ; .idlsym
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_PDATA
                .IF ebx == 'adp.' ; .pdata
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_RDATA
                .IF ebx == 'adr.' ; .rdata
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_RELOC
                .IF ebx == 'ler.' ; .reloc
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_RSRC
                .IF ebx == 'rsr.' ; .rsrc
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_SBSS
                .IF ebx == 'sbs.' ; .sbss
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_SDATA
                .IF ebx == 'ads.' ; .sdata
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_SRDATA
                .IF ebx == 'drs.' ; .srdata
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_SXDATA
                .IF ebx == 'dxs.' ; .sxdata
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_TEXT
                .IF ebx == 'xet.' ; .text
                    mov eax, pCurrentSection
                    ret
                .ENDIF            
            .ELSEIF eax == SEC_TLS
                .IF ebx == 'slt.' ; .tls
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_VSDATA
                .IF ebx == 'dsv.' ; .vsdata
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ELSEIF eax == SEC_XDATA
                .IF ebx == 'adx.' ; .xdata
                    mov eax, pCurrentSection
                    ret
                .ENDIF              
            .ENDIF
        .ENDIF
        
        add pCurrentSection, SIZEOF IMAGE_SECTION_HEADER
        mov ebx, pCurrentSection
        inc nSection
        mov eax, nSection
    .ENDW

    xor eax, eax
    ret
PE_SectionHeaderByType ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_SectionHeaderByAddr - Get section that has dwAddress
; Returns: pointer to section or NULL
;----------------------------------------------------------------------------
PE_SectionHeaderByAddr PROC USES EBX hPE:DWORD, dwAddress:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    xor eax, eax
    ret
PE_SectionHeaderByAddr ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_SectionAdd - Add a new section header to end of section table and a new
; section of specified size and characteristics to end of PE file.
; Returns: TRUE if successful or FALSE otherwise.
;
; Note: If function fails and error is PE_ERROR_SECTION_ADD, then this is a
; fatal error in which the PE file will be closed and the hPE handle will
; be set to NULL. 
;----------------------------------------------------------------------------
PE_SectionAdd PROC USES EBX hPE:DWORD, lpszSectionName:DWORD, dwSectionSize:DWORD, dwSectionCharacteristics:DWORD
    LOCAL dwNewFileSize:DWORD
    
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    
    .IF dwSectionSize == 0
        xor eax, eax
        ret
    .ENDIF
    
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEFilesize
    add eax, dwSectionSize
    add eax, SIZEOF IMAGE_SECTION_HEADER
    mov dwNewFileSize, eax
    Invoke PEIncreaseFileSize, hPE, dwNewFileSize
    .IF eax == TRUE
        ; increment section count in PEINFO and in PE file
        ; adjust offsets and stuff in section header
        ; move everything after section table + SIZEOF IMAGE_SECTION_HEADER
    .ELSE
        Invoke PE_SetError, hPE, PE_ERROR_SECTION_ADD
        xor eax, eax
        ret
    .ENDIF
    
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov eax, TRUE
    ret
PE_SectionAdd ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_SectionDelete - Delete an existing section (by name or index)
; Returns: TRUE if successful or FALSE otherwise.
;
; Note: If function fails and error is PE_ERROR_SECTION_DEL, then this is a
; fatal error in which the PE file will be closed and the hPE handle will
; be set to NULL. 
;----------------------------------------------------------------------------
PE_SectionDelete PROC USES EBX hPE:DWORD, lpszSectionName:DWORD, dwSectionIndex:DWORD
    LOCAL dwNewFileSize:DWORD
    LOCAL dwSectionSize:DWORD
    LOCAL nSection:DWORD
    
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    
    .IF lpszSectionName != NULL ; section name to index 
        ; find section name
    .ELSE ; already have index
        mov eax, dwSectionIndex
    .ENDIF
    mov nSection, eax
    
    ; get existing section size
    ; 
    mov dwSectionSize, eax
    
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEFilesize
    sub eax, dwSectionSize
    sub eax, SIZEOF IMAGE_SECTION_HEADER
    mov dwNewFileSize, eax    
    
    ; Move data down by - SIZEOF IMAGE_SECTION_HEADER
    ; adjust any stuff that needs adjusting
    
    Invoke PEDecreaseFileSize, hPE, dwNewFileSize
    .IF eax == TRUE
        ; Decrement section count in PEINFO and in PE file
        ; adjust offsets and stuff in section header
    .ELSE
        Invoke PE_SetError, hPE, PE_ERROR_SECTION_DEL
        xor eax, eax
        ret
    .ENDIF
    
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    mov eax, TRUE
    ret
PE_SectionDelete ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_SectionInsert - Add and insert a new section.
; Returns: TRUE if successful or FALSE otherwise.
;
; Note: If function fails and error is PE_ERROR_SECTION_INS, then this is a
; fatal error in which the PE file will be closed and the hPE handle will
; be set to NULL. 
;----------------------------------------------------------------------------
PE_SectionInsert PROC USES EBX hPE:DWORD, lpszSectionName:DWORD, dwSectionSize:DWORD, dwSectionCharacteristics:DWORD, dwSectionIndex:DWORD
    LOCAL dwNewFileSize:DWORD
    
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    
    .IF dwSectionSize == 0
        xor eax, eax
        ret
    .ENDIF
    
    ; Call PE_SectionAdd then PE_SectionMove?
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    mov eax, TRUE
    ret
PE_SectionInsert ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_SectionMove - Move section (by name or index) to section (by name or index)
; Returns: TRUE if successful or FALSE otherwise.
;
; Note: If function fails and error is PE_ERROR_SECTION_MOVE, then this is a
; fatal error in which the PE file will be closed and the hPE handle will
; be set to NULL. 
;----------------------------------------------------------------------------
PE_SectionMove PROC USES EBX hPE:DWORD, lpszSectionName:DWORD, dwSectionIndex:DWORD, lpszSectionNameToMoveTo:DWORD, dwSectionIndexToMoveTo:DWORD
    LOCAL nSectionFrom:DWORD
    LOCAL nSectionTo:DWORD
    
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    
    .IF lpszSectionName != NULL
        
    .ELSE
        mov eax, dwSectionIndex
    .ENDIF
    mov nSectionFrom, eax
    
    .IF lpszSectionNameToMoveTo != NULL
        
    .ELSE
        mov eax, dwSectionIndexToMoveTo
    .ENDIF
    mov nSectionTo, eax    
    
    ; check section indexes are within section count and are not same
    
    ; calc blocks of memory to copy/move
     
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    mov eax, TRUE
    ret
PE_SectionMove ENDP



;############################################################################
;  I M P O R T   S E C T I O N   F U N C T I O N S
;############################################################################

PE_ALIGN
;----------------------------------------------------------------------------
; 
;----------------------------------------------------------------------------
PE_ImportDirectoryTable PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEImportDirectoryTable
    ret
PE_ImportDirectoryTable ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; 
;----------------------------------------------------------------------------

PE_ImportLookupTable PROC USES EBX hPE:DWORD, dwImportDirectoryEntryIndex:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    ret
PE_ImportLookupTable ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; 
;----------------------------------------------------------------------------

PE_ImportHintNameTable PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    ret
PE_ImportHintNameTable ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; 
;----------------------------------------------------------------------------

PE_ImportAddressTable PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    ret
PE_ImportAddressTable ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; 
;----------------------------------------------------------------------------
PE_ImportDirectoryEntryCount PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEImportDirectoryCount
    ret
PE_ImportDirectoryEntryCount ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_ImportDirectoryEntryDLL - return address of DLL string, or NULL
;----------------------------------------------------------------------------
PE_ImportDirectoryEntryDLL PROC USES EBX hPE:DWORD, dwImportDirectoryEntryIndex:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEImportDirectoryCount
    .IF dwImportDirectoryEntryIndex >= eax
        mov eax, 0
        ret
    .ENDIF
    ; eax contains PEImportDirectoryCount
    mov ebx, SIZEOF IMAGE_IMPORT_DESCRIPTOR
    mul ebx
    mov ebx, eax ; store in ebx
    Invoke PE_ImportDirectoryTable, hPE
    .IF eax == 0
        ret
    .ENDIF
    
    ; RVAToOffset
    
    add ebx, eax ; offset to specific entry in ebx 
    mov eax, [ebx].IMAGE_IMPORT_DESCRIPTOR.Name1
    ; eax has pointer to DLL name
    ret
PE_ImportDirectoryEntryDLL ENDP





;############################################################################
;  I N F O   F U N C T I O N S
;############################################################################

PE_ALIGN
;----------------------------------------------------------------------------
; PE_Machine - returns machine id in eax
;----------------------------------------------------------------------------
PE_Machine PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    Invoke PE_HeaderFile, hPE
    mov ebx, eax
    movzx eax, word ptr [ebx].IMAGE_FILE_HEADER.Machine
    ret
PE_Machine ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_Characteristics - returns characteristics bit flags in eax
;----------------------------------------------------------------------------
PE_Characteristics PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    Invoke PE_HeaderFile, hPE
    mov ebx, eax
    movzx eax, word ptr [ebx].IMAGE_FILE_HEADER.Characteristics
    ret
PE_Characteristics ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_LinkerVersion - returns major and minor linker version in ax 
;----------------------------------------------------------------------------
PE_LinkerVersion PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    Invoke PE_HeaderOptional, hPE
    mov ebx, eax
    
    Invoke PE_Is64, hPE
    .IF eax == TRUE
        movzx eax, byte ptr [ebx].IMAGE_OPTIONAL_HEADER64.MajorLinkerVersion
        mov ah, al
        movzx ebx, byte ptr [ebx].IMAGE_OPTIONAL_HEADER64.MinorLinkerVersion
        mov al, bl
    .ELSE    
        movzx eax, byte ptr [ebx].IMAGE_OPTIONAL_HEADER32.MajorLinkerVersion
        mov ah, al
        movzx ebx, byte ptr [ebx].IMAGE_OPTIONAL_HEADER32.MinorLinkerVersion
        mov al, bl
    .ENDIF
    ret
PE_LinkerVersion ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_AddressOfEntryPoint - returns OEP in eax
;----------------------------------------------------------------------------
PE_AddressOfEntryPoint PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    Invoke PE_HeaderOptional, hPE
    mov ebx, eax
    
    Invoke PE_Is64, hPE
    .IF eax == TRUE
        mov eax, [ebx].IMAGE_OPTIONAL_HEADER64.AddressOfEntryPoint
    .ELSE
        mov eax, [ebx].IMAGE_OPTIONAL_HEADER32.AddressOfEntryPoint
    .ENDIF
    ret
PE_AddressOfEntryPoint ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_ImageBase - returns imagebase in eax for PE32, eax:edx for PE32+ (PE64)
;----------------------------------------------------------------------------
PE_ImageBase PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PE64
    .IF eax == TRUE
        mov eax, dword ptr [ebx].PEINFO.PE64ImageBase
        mov edx, dword ptr [ebx+4].PEINFO.PE64ImageBase
    .ELSE
        mov eax, [ebx].PEINFO.PEImageBase
        xor edx, edx
    .ENDIF
    ret
PE_ImageBase ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_ImageBase - returns size of image in eax
;----------------------------------------------------------------------------
PE_SizeOfImage PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    Invoke PE_HeaderOptional, hPE
    mov ebx, eax
    
    Invoke PE_Is64, hPE
    .IF eax == TRUE
        mov eax, [ebx].IMAGE_OPTIONAL_HEADER64.SizeOfImage
    .ELSE
        mov eax, [ebx].IMAGE_OPTIONAL_HEADER32.SizeOfImage
    .ENDIF
    ret
PE_SizeOfImage ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_CheckSum - returns checksum in eax
;----------------------------------------------------------------------------
PE_CheckSum PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    Invoke PE_HeaderOptional, hPE
    mov ebx, eax
    
    Invoke PE_Is64, hPE
    .IF eax == TRUE
        mov eax, [ebx].IMAGE_OPTIONAL_HEADER64.CheckSum
    .ELSE
        mov eax, [ebx].IMAGE_OPTIONAL_HEADER32.CheckSum
    .ENDIF
    ret
PE_CheckSum ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_Subsystem - returns subsystem id in eax
;----------------------------------------------------------------------------
PE_Subsystem PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    Invoke PE_HeaderOptional, hPE
    mov ebx, eax
    
    Invoke PE_Is64, hPE
    .IF eax == TRUE
        movzx eax, word ptr [ebx].IMAGE_OPTIONAL_HEADER64.Subsystem
    .ELSE
        movzx eax, word ptr [ebx].IMAGE_OPTIONAL_HEADER32.Subsystem
    .ENDIF
    ret
PE_Subsystem ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_DllCharacteristics - returns dll characteristics bit flags in eax
;----------------------------------------------------------------------------
PE_DllCharacteristics PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    Invoke PE_HeaderOptional, hPE
    mov ebx, eax
    
    Invoke PE_Is64, hPE
    .IF eax == TRUE
        movzx eax, word ptr [ebx].IMAGE_OPTIONAL_HEADER64.DllCharacteristics
    .ELSE
        movzx eax, word ptr [ebx].IMAGE_OPTIONAL_HEADER32.DllCharacteristics
    .ENDIF    
    ret
PE_DllCharacteristics ENDP


PE_ALIGN
;----------------------------------------------------------------------------
; PE_IsDll - returns TRUE if DLL or FALSE otherwise
;----------------------------------------------------------------------------
PE_IsDll PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEDLL
    ret
PE_IsDll ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_Is64 - returns TRUE if PE32+ (PE64) or FALSE if PE32
;----------------------------------------------------------------------------
PE_Is64 PROC USES EBX hPE:DWORD
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PE64
    ret
PE_Is64 ENDP




;############################################################################
;  E R R O R   F U N C T I O N S
;############################################################################

PE_ALIGN
;----------------------------------------------------------------------------
; PE_SetError
;----------------------------------------------------------------------------
PE_SetError PROC USES EBX hPE:DWORD, dwError:DWORD
    .IF hPE != NULL && dwError != PE_ERROR_SUCCESS
        mov ebx, hPE
        mov ebx, [ebx].PEINFO.PEHandle 
        .IF ebx != 0
            mov eax, 0 ; null out hPE handle if it exists
            mov [ebx], eax
        .ENDIF
    .ENDIF
    mov eax, dwError
    mov PELIB_ErrorNo, eax
    ret
PE_SetError ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_GetError
;----------------------------------------------------------------------------
PE_GetError PROC
    mov eax, PELIB_ErrorNo
    ret
PE_GetError ENDP




;############################################################################
;  H E L P E R   F U N C T I O N S
;############################################################################

PE_ALIGN
;----------------------------------------------------------------------------
; PE_RVAToOffset
;----------------------------------------------------------------------------
PE_RVAToOffset PROC USES EBX EDX hPE:DWORD, dwRVA:DWORD
    LOCAL nTotalSections:DWORD
    LOCAL nCurrentSection:DWORD
    LOCAL pCurrentSection:DWORD
    
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PESectionCount
    mov nTotalSections, eax
    mov eax, [ebx].PEINFO.PESectionTable
    mov pCurrentSection, eax
    mov ebx, eax
    mov edx, dwRVA
    mov eax, 0
    mov nCurrentSection, 0
    .WHILE eax < nTotalSections
        mov eax, [ebx].IMAGE_SECTION_HEADER.VirtualAddress
        .IF edx >= eax 
            add eax, [ebx].IMAGE_SECTION_HEADER.SizeOfRawData
            .IF edx < eax ; The address is in this section
                mov eax, [ebx].IMAGE_SECTION_HEADER.VirtualAddress
                sub edx, eax
                mov eax, [ebx].IMAGE_SECTION_HEADER.PointerToRawData
                add eax, edx ; eax == file offset
                ret
            .ENDIF
        .ENDIF
        
        add pCurrentSection, SIZEOF IMAGE_SECTION_HEADER
        mov ebx, pCurrentSection
        inc nCurrentSection
        mov eax, nCurrentSection
    .ENDW
    mov eax, edx
    ret
PE_RVAToOffset ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; PE_OffsetToRVA
;----------------------------------------------------------------------------
PE_OffsetToRVA PROC USES EBX hPE:DWORD, dwOffset:DWORD
    LOCAL nTotalSections:DWORD
    LOCAL nCurrentSection:DWORD
    LOCAL pCurrentSection:DWORD
    
    .IF hPE == NULL
        Invoke PE_SetError, NULL, PE_ERROR_NO_HANDLE
        xor eax, eax
        ret
    .ENDIF
    Invoke PE_SetError, NULL, PE_ERROR_SUCCESS
    
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PESectionCount
    mov nTotalSections, eax
    mov eax, [ebx].PEINFO.PESectionTable
    mov pCurrentSection, eax
    mov ebx, eax
    mov edx, dwOffset
    mov eax, 0
    mov nCurrentSection, 0
    .WHILE eax < nTotalSections
        mov eax, [ebx].IMAGE_SECTION_HEADER.PointerToRawData
        .IF edx >= eax 
            add eax, [ebx].IMAGE_SECTION_HEADER.SizeOfRawData
            .IF edx < eax ; The address is in this section
                mov eax, [ebx].IMAGE_SECTION_HEADER.PointerToRawData
                sub edx, eax
                mov eax, [ebx].IMAGE_SECTION_HEADER.VirtualAddress
                add eax, edx ; eax == file offset
                ret
            .ENDIF
        .ENDIF
        
        add pCurrentSection, SIZEOF IMAGE_SECTION_HEADER
        mov ebx, pCurrentSection
        inc nCurrentSection
        mov eax, nCurrentSection
    .ENDW
    xor eax, eax
    ret
PE_OffsetToRVA ENDP




;############################################################################
;  I N T E R N A L   F U N C T I O N S
;############################################################################

PE_ALIGN
;----------------------------------------------------------------------------
; Checks the PE signatures to determine if they are valid
;----------------------------------------------------------------------------
PESignature PROC USES EBX pPEInMemory:DWORD
    mov ebx, pPEInMemory
    movzx eax, word ptr [ebx].IMAGE_DOS_HEADER.e_magic
    .IF ax == MZ_SIGNATURE
        add ebx, [ebx].IMAGE_DOS_HEADER.e_lfanew
        ; ebx is pointer to IMAGE_NT_HEADERS now
        mov eax, [ebx].IMAGE_NT_HEADERS.Signature
        .IF ax == PE_SIGNATURE
            movzx eax, word ptr [ebx].IMAGE_NT_HEADERS.OptionalHeader.Magic
            .IF ax == IMAGE_NT_OPTIONAL_HDR32_MAGIC
                mov eax, PE_ARCH_32
                ret
            .ELSEIF ax == IMAGE_NT_OPTIONAL_HDR64_MAGIC
                mov eax, PE_ARCH_64
                ret
            .ENDIF
        .ENDIF
    .ENDIF
    mov eax, PE_INVALID
    ret
PESignature ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; Increase (resize) PE file. Adjustments to pointers and other data to be handled by 
; other functions.
; Returns: TRUE on success or FALSE otherwise. 
;----------------------------------------------------------------------------
PEIncreaseFileSize PROC USES EBX hPE:DWORD, dwNewSize:DWORD
    LOCAL bReadOnly:DWORD
    LOCAL PEFilesize:DWORD
    LOCAL hPEFile:DWORD
    LOCAL PEMemMapHandle:DWORD
    LOCAL PEMemMapPtr:DWORD
    LOCAL PENewFileSize:DWORD
    LOCAL PENewMemMapHandle:DWORD
    LOCAL PENewMemMapPtr:DWORD    
    
    .IF hPE == NULL || dwNewSize == 0
        xor eax, eax
        ret
    .ENDIF
    
    ;---------------------------------------------------
    ; Get existing file, map and view handles
    ;---------------------------------------------------
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEFilesize
    .IF dwNewSize <= eax ; if size is less than existing file's size
        xor eax, eax
        ret
    .ENDIF
    mov PEFilesize, eax
    mov eax, [ebx].PEINFO.PEOpenMode
    mov bReadOnly, eax
    mov eax, [ebx].PEINFO.PEFileHandle
    mov hPEFile, eax
    mov eax, [ebx].PEINFO.PEMemMapHandle
    mov PEMemMapHandle, eax
    mov eax, [ebx].PEINFO.PEMemMapPtr
    mov PEMemMapPtr, eax
    
    ;---------------------------------------------------
    ; Create file mapping of new size
    ;---------------------------------------------------
    mov eax, dwNewSize
    mov PENewFileSize, eax
    .IF bReadOnly == TRUE
        Invoke CreateFileMapping, hPEFile, NULL, PAGE_READONLY, 0, dwNewSize, NULL ; Create memory mapped file
    .ELSE
        Invoke CreateFileMapping, hPEFile, NULL, PAGE_READWRITE, 0, dwNewSize, NULL ; Create memory mapped file
    .ENDIF
    .IF eax == NULL
        xor eax, eax
        ret
    .ENDIF
    mov PENewMemMapHandle, eax
    
    ;---------------------------------------------------
    ; Map the view
    ;---------------------------------------------------
    .IF bReadOnly == TRUE
        Invoke MapViewOfFileEx, PENewMemMapHandle, FILE_MAP_READ, 0, 0, 0, NULL
    .ELSE
        Invoke MapViewOfFileEx, PENewMemMapHandle, FILE_MAP_ALL_ACCESS, 0, 0, 0, NULL
    .ENDIF    
    .IF eax == NULL
        Invoke CloseHandle, PENewMemMapHandle
        xor eax, eax
        ret
    .ENDIF
    mov PENewMemMapPtr, eax

    ;---------------------------------------------------
    ; Close existing mapping and only use new one now
    ;---------------------------------------------------
    Invoke UnmapViewOfFile, PEMemMapPtr
    Invoke CloseHandle, PEMemMapHandle
    
    ;---------------------------------------------------
    ; Update handles and information
    ;---------------------------------------------------
    mov ebx, hPE
    mov eax, PENewMemMapPtr
    mov [ebx].PEINFO.PEMemMapPtr, eax    
    mov eax, PENewMemMapHandle
    mov [ebx].PEINFO.PEMemMapHandle, eax
    mov eax, PENewFileSize
    mov [ebx].PEINFO.PEFilesize, eax

    mov eax, TRUE
    ret
PEIncreaseFileSize ENDP

PE_ALIGN
;----------------------------------------------------------------------------
; Decrease (resize) PE file. Adjustments to pointers and other data to be handled by 
; other functions. Move data before calling this.
; Returns: TRUE on success or FALSE otherwise. 
;----------------------------------------------------------------------------
PEDecreaseFileSize PROC USES EBX hPE:DWORD, dwNewSize:DWORD
    LOCAL bReadOnly:DWORD
    LOCAL PEFilesize:DWORD
    LOCAL hPEFile:DWORD
    LOCAL PEMemMapHandle:DWORD
    LOCAL PEMemMapPtr:DWORD
    LOCAL PENewFileSize:DWORD
    LOCAL PENewMemMapHandle:DWORD
    LOCAL PENewMemMapPtr:DWORD    
    
    .IF hPE == NULL || dwNewSize == 0
        xor eax, eax
        ret
    .ENDIF
    
    ;---------------------------------------------------
    ; Get existing file, map and view handles
    ;---------------------------------------------------
    mov ebx, hPE
    mov eax, [ebx].PEINFO.PEFilesize
    .IF dwNewSize > eax ; if size is greater than existing file's size
        xor eax, eax
        ret
    .ENDIF
    mov PEFilesize, eax
    mov eax, [ebx].PEINFO.PEOpenMode
    mov bReadOnly, eax
    mov eax, [ebx].PEINFO.PEFileHandle
    mov hPEFile, eax
    mov eax, [ebx].PEINFO.PEMemMapHandle
    mov PEMemMapHandle, eax
    mov eax, [ebx].PEINFO.PEMemMapPtr
    mov PEMemMapPtr, eax    
    
    ;---------------------------------------------------
    ; Close existing mapping 
    ;---------------------------------------------------
    Invoke UnmapViewOfFile, PEMemMapPtr
    Invoke CloseHandle, PEMemMapHandle
    
    Invoke SetFilePointer, hPEFile, dwNewSize, 0, FILE_BEGIN
    Invoke SetEndOfFile, hPEFile
    Invoke FlushFileBuffers, hPEFile
    
    ;---------------------------------------------------
    ; Create file mapping of new size
    ;---------------------------------------------------
    mov eax, dwNewSize
    mov PENewFileSize, eax
    .IF bReadOnly == TRUE
        Invoke CreateFileMapping, hPEFile, NULL, PAGE_READONLY, 0, 0, NULL ; Create memory mapped file
    .ELSE
        Invoke CreateFileMapping, hPEFile, NULL, PAGE_READWRITE, 0, 0, NULL ; Create memory mapped file
    .ENDIF
    .IF eax == NULL
        xor eax, eax
        ret
    .ENDIF
    mov PENewMemMapHandle, eax
    
    ;---------------------------------------------------
    ; Map the view
    ;---------------------------------------------------
    .IF bReadOnly == TRUE
        Invoke MapViewOfFileEx, PENewMemMapHandle, FILE_MAP_READ, 0, 0, 0, NULL
    .ELSE
        Invoke MapViewOfFileEx, PENewMemMapHandle, FILE_MAP_ALL_ACCESS, 0, 0, 0, NULL
    .ENDIF    
    .IF eax == NULL
        Invoke CloseHandle, PENewMemMapHandle
        xor eax, eax
        ret
    .ENDIF
    mov PENewMemMapPtr, eax    
    
    ;---------------------------------------------------
    ; Update handles and information
    ;---------------------------------------------------
    mov ebx, hPE
    mov eax, PENewMemMapPtr
    mov [ebx].PEINFO.PEMemMapPtr, eax    
    mov eax, PENewMemMapHandle
    mov [ebx].PEINFO.PEMemMapHandle, eax
    mov eax, PENewFileSize
    mov [ebx].PEINFO.PEFilesize, eax
    
    mov eax, TRUE
    ret
PEDecreaseFileSize ENDP


END






















