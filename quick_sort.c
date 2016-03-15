#include <stdio.h>
int main(){
    int n,i,j,k,f;
    scanf("%d",&n);
    int number[n];
    for(i = 0; i < n; i++){
        scanf("%d",&number[i]);
    }
    for(j = 0; j < n-1; j++){
        for(k =0; k < n-j; k++){
            if(number[k] > number[k+1]){
            int tmp = number[k];
            number[k] = number[k+1];
            number[k+1] = tmp;    
            }
        }
    }
    for(f = 0; f < n; f++){
        printf("%d  ",number[f]);
    }


}
