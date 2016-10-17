#include<stdio.h>

main()
{
  int minimum=0;
  int maximum=200;
  int step=20;
  int tmp=0;
  while(tmp<=maximum)
	{
          printf("%d\t%d\n",tmp,5*(tmp-32)/9);
          tmp=tmp+step;
        }
}

