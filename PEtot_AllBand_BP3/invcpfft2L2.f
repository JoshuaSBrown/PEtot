      subroutine invcpfft2L2(psi,nr1L2,nr2L2,nr3L2)

c     Written by A. Canning (CRAY-EPFL) 25th July 94  
c     
c     output = psi(z,y,x)  wavefunction in real space z columns 
c     input  = psi(x,y,z)  x columns of g vectors in load balalanced distr.
c     
c     computes inverse fft specifically for CP algo 
c     ie taking sphere and going to cylinder then two (one for gamma)
c     slices then a complete cube. 
c     see fftprep.f for more details
c     fftprep must be called once before this routine
c     for setups.
c     
c     last revised ADV 7/7/95 to parametrise the no. of 
c     chunks on each PE
c     AMC revised 21/6/97 hardwired for gamma point complex to real fft

      use load_data
      use fft_data
      use data
      
      implicit none

      include "mpif.h"
c     
c     
      real*8,allocatable,dimension(:) :: worknr1,worknr2,worknr3
      real*8,allocatable,dimension(:) :: psiy,combuf1,combuf2
      
      integer inode, nnodes, inode_tot, nnodes_tot
      integer nnodes_k, nnodes_b, inode_k, inode_b
      integer icolor_k, icolor_b, ikey_k, ikey_b, icolor, ikey
      integer num_group_k, num_group_b
      integer MPI_COMM_K1, MPI_COMM_K2, MPI_COMM_B1, MPI_COMM_B2
      integer MPI_COMM_K, MPI_COMM_N

      common /mpi_data/inode,nnodes,inode_tot,nnodes_tot,
     &     nnodes_k, nnodes_b, inode_k, inode_b,
     &     icolor_k, icolor_b, ikey_k, ikey_b, icolor, ikey,
     &     num_group_k, num_group_b, 
     &     MPI_COMM_K1, MPI_COMM_K2, MPI_COMM_B1, MPI_COMM_B2,
     &     MPI_COMM_K, MPI_COMM_N

      integer ireq(nnodes)

      integer jj

      integer mpistatus(mpi_status_size)

c     scalars used

      integer i,ib,ic,idum,ii,ilocadd,isc,isign,itar,itaradd,
     c     itnode,iw,ix,iy,izb,j,jcol,ngy,ngyadd,ngz,nr1L2,
     c     nr2L2,nr3L2,nr3uL2,iloc_dum,ierr
      integer nworknr1,nworknr2,nworknr3

      real*8 psi(mr_nL2)
      real*8 psidum(nr3L2),sum

      nworknr1 = 20000+2.28*nr1xL2
      nworknr2 = 20000+2.28*nr2xL2
      nworknr3 = 20000+2.28*nr3xL2

cccc  

      allocate(worknr1(nworknr1))
      allocate(worknr2(nworknr2))
      allocate(worknr3(nworknr3))
      allocate(psiy(mr_nL2))
      allocate(combuf1(mr_nL2))
      allocate(combuf2(mr_nL2))


      call mpi_barrier(MPI_COMM_K,ierr)

c     
c     for gamma point fft
c     
      nr3uL2 = nr3L2/2 + 1
c     
c     memory allocation for local arrays used with SHMEM routines
c     
c     
      isign = -1
c     
c     do the FFT's in place on the non-zero columns 
c     of psi
c     so this is the x dir FFT
c     



      do jcol = 1,ncol2L2(inode)
         ilocadd = 1+(jcol-1)*(2*nr1L2)

         call system_ccfft(0,isign,nr1L2,1.0d0,psi(ilocadd),
     &    psi(ilocadd),tabnr1linL2,worknr1,0,ntabnr1L2,nworknr1)


      enddo                     !i


c     
c     transpose to the slice  y col mode  in psiy
c     
      do ii = 1,ncoly2L2*2*nr2L2
         psiy(ii) = 0.0
      enddo

      idum = 1
      do i = 1,nnodes
        do j = 1,ivpacn1lL2(i)
          combuf1(idum) = psi(ivpac1lL2(idum))
          idum = idum + 1
        enddo
      enddo

      call mpi_barrier(mpi_comm_k,ierr)


      idum = 1
      do i = 1,nnodes
       call mpi_isend(combuf1(idum),ivpacn1lL2(i),mpi_real8,i-1,
     &             inode,mpi_comm_k,ireq(i),ierr)
       idum = idum + ivpacn1lL2(i)
      enddo


      idum = 1
      do i = 1,nnodes
       call mpi_recv(combuf2(idum),ivunpn1lL2(i),mpi_real8,i-1,i,
     &               mpi_comm_k,mpistatus,ierr)
       idum = idum + ivunpn1lL2(i)
      enddo


      do i = 1, nnodes
        call mpi_wait(ireq(i), mpistatus, ierr)
      end do

      call mpi_barrier(mpi_comm_k,ierr)

      idum = 1
      do i = 1,nnodes
        do j = 1,ivunpn1lL2(i)
          psiy(ivunp1lL2(idum)) = combuf2(idum)
          idum = idum + 1
        enddo
      enddo
c     
c     do FFT on the y direction on the two (one for gamma) slices 
c     this is the y dir FFT
c     each PE should have ncoly columns for the FFT
c     


      do i = 1,ncoly2L2
         ilocadd = 1+(i-1)*(2*nr2L2)
         call system_ccfft(0,isign,nr2L2,1.0d0,psiy(ilocadd),
     c      psiy(ilocadd),tabnr2linL2,worknr2,0,ntabnr2L2,nworknr2)
      enddo


c
c     now use strided put to put the z strips to the correct
c     processors. Put them into psi.
c     zero values of psi which we do not put into


      do i = 1,ncolz2L2
         idum = (i-1)*2*nr3uL2
         do j = 2*mgz2L2+1,2*nr3uL2
            psi(idum+j)=0.0
         enddo
      enddo


      idum = 1
      do i = 1,nnodes
        do j = 1,ivpacn2lL2(i)
          combuf1(idum) = psiy(ivpac2lL2(idum))
          idum  = idum + 1
        enddo
      enddo


      call mpi_barrier(mpi_comm_k,ierr)


      idum = 1
      do i = 1,nnodes
       call mpi_isend(combuf1(idum),ivpacn2lL2(i),mpi_real8,i-1,inode,
     &                mpi_comm_k,ireq(i),ierr)
       idum = idum + ivpacn2lL2(i)
      enddo


      idum = 1
      do i = 1,nnodes
       call mpi_recv(combuf2(idum),ivunpn2lL2(i),mpi_real8,i-1,i,
     &               mpi_comm_k,mpistatus,ierr)
       idum = idum + ivunpn2lL2(i)
      enddo


      do i = 1, nnodes
        call mpi_wait(ireq(i), mpistatus, ierr)
      end do

      call mpi_barrier(mpi_comm_k,ierr)


      idum = 1
      do i = 1,nnodes
        do j = 1,ivunpn2lL2(i)
          psi(ivunp2lL2(idum)) = combuf2(idum)
          idum = idum + 1
        enddo
      enddo
c

c     
c     now do FFT's on z direction so each proc has nr1*nr2/nnodes 
c     columns of height nr3 complex numbers (real for gamma point)
c     



      do i = 1,ncolzL2
         ilocadd = 1+(i-1)*(2*nr3uL2)

         call system_csfft(0,isign,nr3L2,1.0d0,psi(ilocadd),
     &    psidum,tabnr3lcrL2,worknr3,0,ntabnr3L2,nworknr3)

         iloc_dum = 1+(i-1)*nr3L2

         do ii = 1,nr3L2
            psi(iloc_dum-1+ii)=psidum(ii)
         enddo

      enddo


      call mpi_barrier(mpi_comm_k,ierr)

      deallocate(worknr1)
      deallocate(worknr2)
      deallocate(worknr3)
      deallocate(psiy)
      deallocate(combuf1)
      deallocate(combuf2)

      end
      


