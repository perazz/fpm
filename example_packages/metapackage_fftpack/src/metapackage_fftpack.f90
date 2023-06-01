module metapackage_fftpack
  use fftpack, only: rk
  use iso_fortran_env, only: real64
  implicit none
  private

  public :: simple_test
contains
  subroutine simple_test(success)
    logical, intent(out) :: success 
    ! Success! can read fftpack module
    success = rk == real64 
  end subroutine simple_test 
end module metapackage_fftpack
