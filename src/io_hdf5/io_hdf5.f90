#include "boltzplatz.h"

MODULE MOD_IO_HDF5
!===================================================================================================================================
! Add comments please!
!===================================================================================================================================
! MODULES
USE HDF5
USE MOD_Globals,ONLY: iError
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
LOGICAL                  :: gatheredWrite
INTEGER(HID_T)           :: File_ID
INTEGER(HSIZE_T),POINTER :: HSize(:)
INTEGER                  :: nDims
INTEGER                  :: MPIInfo !for lustre file system

INTERFACE InitIO
  MODULE PROCEDURE InitIO_HDF5
END INTERFACE

INTERFACE OpenDataFile
  MODULE PROCEDURE OpenHDF5File
END INTERFACE

INTERFACE CloseDataFile
  MODULE PROCEDURE CloseHDF5File
END INTERFACE

!===================================================================================================================================

CONTAINS

SUBROUTINE InitIO_HDF5()
!===================================================================================================================================
! Initialize HDF5 IO
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Globals_Vars,       ONLY:ProjectName
USE MOD_ReadInTools,        ONLY:GETLOGICAL,CNTSTR, GETSTR
#ifdef INTEL
USE IFPORT
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=300)             :: IniFile
!===================================================================================================================================

gatheredWrite=.FALSE.
IF(nLeaderProcs.LT.nProcessors) gatheredWrite=GETLOGICAL('gatheredWrite','.FALSE.')
#ifdef MPI
  CALL MPI_Info_Create(MPIInfo, iError)

  !normal case:
  MPIInfo=MPI_INFO_NULL

  ! Large block IO extremely slow on Juqeen cluster (only available on IBM clusters)
  !CALL MPI_Info_set(MPIInfo, "IBM_largeblock_io", "true", ierror)
#ifdef LUSTRE
  CALL MPI_Info_Create(MPIInfo, iError)
  ! For lustre file system:
  ! Disables ROMIO's data-sieving 
  CALL MPI_Info_set(MPIInfo, "romio_ds_read", "disable",iError)
  CALL MPI_Info_set(MPIInfo, "romio_ds_write","disable",iError)
  ! Enable ROMIO's collective buffering 
  CALL MPI_Info_set(MPIInfo, "romio_cb_read", "enable", iError)
  CALL MPI_Info_set(MPIInfo, "romio_cb_write","enable", iError)
#endif
#endif /* MPI */
END SUBROUTINE InitIO_HDF5


#ifdef MPI
SUBROUTINE OpenHDF5File(FileString,create,single,communicatorOpt,userblockSize)
#else
SUBROUTINE OpenHDF5File(FileString,create,userblockSize)
#endif
!===================================================================================================================================
! Open HDF5 file and groups
!===================================================================================================================================
! MODULES
USE MOD_Globals
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN)   :: FileString
LOGICAL,INTENT(IN)            :: create
#ifdef MPI
LOGICAL,INTENT(IN)            :: single
INTEGER,INTENT(IN),OPTIONAL   :: communicatorOpt
#endif
INTEGER,INTENT(IN),OPTIONAL   :: userblockSize  !< size of the file to be prepended to HDF5 file
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER(HID_T)                 :: Plist_ID
#ifdef MPI
INTEGER                        :: comm
#endif
LOGICAL                        :: fileExists
INTEGER(HSIZE_T)               :: userblockSize_loc, tmp, tmp2
!===================================================================================================================================
LOGWRITE(*,'(A)')'  OPEN HDF5 FILE "',TRIM(FileString),'" ...'

userblockSize_loc = 0
IF (PRESENT(userblockSize)) userblockSize_loc = userblockSize

! Initialize FORTRAN predefined datatypes
CALL H5OPEN_F(iError)

! Setup file access property list with parallel I/O access (MPI) or with default property list.
IF(create)THEN
  CALL H5PCREATE_F(H5P_FILE_CREATE_F, Plist_ID, iError)
  IF(iError.NE.0) CALL abort(__STAMP__,&
    'ERROR: Could not create file '//TRIM(FileString))
ELSE
  CALL H5PCREATE_F(H5P_FILE_ACCESS_F, Plist_ID, iError)
  IF(iError.NE.0) CALL abort(__STAMP__,&
    'ERROR: Could not open file '//TRIM(FileString))
END IF

#ifdef MPI
comm = MERGE(communicatorOpt,MPI_COMM_WORLD,PRESENT(communicatorOpt))
IF(.NOT.single)  CALL H5PSET_FAPL_MPIO_F(Plist_ID, comm, MPIInfo, iError)
#endif /* MPI */

! Open the file collectively.
IF(create)THEN
  IF (userblockSize_loc > 0) THEN
    tmp = userblockSize_loc/512
    IF (MOD(userblockSize_loc,512).GT.0) tmp = tmp+1
    tmp2 = 512*2**CEILING(LOG(REAL(tmp))/LOG(2.))
    CALL H5PSET_USERBLOCK_F(Plist_ID, tmp2, iError)
  END IF
  CALL H5FCREATE_F(TRIM(FileString), H5F_ACC_TRUNC_F, File_ID, iError, creation_prp = Plist_ID)
ELSE !read-only ! and write (added later)
  INQUIRE(FILE=TRIM(FileString),EXIST=fileExists)
  IF(.NOT.fileExists) CALL abort(&
__STAMP__&
, 'ERROR: Specified file '//TRIM(FileString)//' does not exist.')
  CALL H5FOPEN_F(  TRIM(FileString), H5F_ACC_RDWR_F,  File_ID, iError, access_prp = Plist_ID)
END IF
IF(iError.NE.0) CALL abort(&
__STAMP__&
,'ERROR: Could not open or create file '//TRIM(FileString)) 

CALL H5PCLOSE_F(Plist_ID, iError)
LOGWRITE(*,*)'...DONE!'
END SUBROUTINE OpenHDF5File



SUBROUTINE CloseHDF5File()
!===================================================================================================================================
! Close HDF5 file and groups
!===================================================================================================================================
! MODULES
USE MOD_Globals,ONLY:UNIT_stdOut,UNIT_logOut,Logging
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
LOGWRITE(*,'(A)')'  CLOSE HDF5 FILE...'
! Close file
CALL H5FCLOSE_F(File_ID, iError)
! Close FORTRAN predefined datatypes.
CALL H5CLOSE_F(iError)
File_ID=0
LOGWRITE(*,*)'...DONE!'
END SUBROUTINE CloseHDF5File

END MODULE MOD_io_HDF5
