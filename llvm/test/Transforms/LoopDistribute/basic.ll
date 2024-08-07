; RUN: opt -aa-pipeline=basic-aa -passes=loop-distribute -enable-loop-distribute -verify-loop-info -verify-dom-info -S \
; RUN:   < %s | FileCheck %s

; RUN: opt -aa-pipeline=basic-aa -passes='loop-distribute,print<access-info>' -enable-loop-distribute \
; RUN:   -verify-loop-info -verify-dom-info -disable-output < %s 2>&1 | FileCheck %s --check-prefix=ANALYSIS

; RUN: opt -aa-pipeline=basic-aa -passes=loop-distribute,loop-vectorize -enable-loop-distribute -force-vector-width=4 -S \
; RUN:   < %s | FileCheck %s --check-prefix=VECTORIZE

; We should distribute this loop into a safe (2nd statement) and unsafe loop
; (1st statement):
;   for (i = 0; i < n; i++) {
;     A[i + 1] = A[i] * B[i];
;     =======================
;     C[i] = D[i] * E[i];
;   }

; CHECK-LABEL: @f(
define void @f(ptr noalias %a, ptr noalias %b, ptr noalias %c, ptr noalias %d, ptr noalias %e) {
entry:
  br label %for.body

; Verify the two distributed loops.

; CHECK: entry.split.ldist1:
; CHECK:    br label %for.body.ldist1
; CHECK: for.body.ldist1:
; CHECK:    %mulA.ldist1 = mul i32 %loadB.ldist1, %loadA.ldist1
; CHECK:    br i1 %exitcond.ldist1, label %entry.split, label %for.body.ldist1

; CHECK: entry.split:
; CHECK:    br label %for.body
; CHECK: for.body:
; CHECK:    %mulC = mul i32 %loadD, %loadE
; CHECK: for.end:


; ANALYSIS: for.body.ldist1:
; ANALYSIS-NEXT: Report: unsafe dependent memory operations in loop
; ANALYSIS: for.body:
; ANALYSIS-NEXT: Memory dependences are safe{{$}}


; VECTORIZE: mul <4 x i32>

for.body:                                         ; preds = %for.body, %entry
  %ind = phi i64 [ 0, %entry ], [ %add, %for.body ]

  %arrayidxA = getelementptr inbounds i32, ptr %a, i64 %ind
  %loadA = load i32, ptr %arrayidxA, align 4

  %arrayidxB = getelementptr inbounds i32, ptr %b, i64 %ind
  %loadB = load i32, ptr %arrayidxB, align 4

  %mulA = mul i32 %loadB, %loadA

  %add = add nuw nsw i64 %ind, 1
  %arrayidxA_plus_4 = getelementptr inbounds i32, ptr %a, i64 %add
  store i32 %mulA, ptr %arrayidxA_plus_4, align 4

  %arrayidxD = getelementptr inbounds i32, ptr %d, i64 %ind
  %loadD = load i32, ptr %arrayidxD, align 4

  %arrayidxE = getelementptr inbounds i32, ptr %e, i64 %ind
  %loadE = load i32, ptr %arrayidxE, align 4

  %mulC = mul i32 %loadD, %loadE

  %arrayidxC = getelementptr inbounds i32, ptr %c, i64 %ind
  store i32 %mulC, ptr %arrayidxC, align 4

  %exitcond = icmp eq i64 %add, 20
  br i1 %exitcond, label %for.end, label %for.body

for.end:                                          ; preds = %for.body
  ret void
}

declare i32 @llvm.convergent(i32) #0

; It is OK to distribute with a convergent operation, since in each
; new loop the convergent operation has the ssame control dependency.
; CHECK-LABEL: @f_with_convergent(
define void @f_with_convergent(ptr noalias %a, ptr noalias %b, ptr noalias %c, ptr noalias %d, ptr noalias %e) {
entry:
  br label %for.body

; Verify the two distributed loops.

; CHECK: entry.split.ldist1:
; CHECK:    br label %for.body.ldist1
; CHECK: for.body.ldist1:
; CHECK:    %mulA.ldist1 = mul i32 %loadB.ldist1, %loadA.ldist1
; CHECK:    br i1 %exitcond.ldist1, label %entry.split, label %for.body.ldist1

; CHECK: entry.split:
; CHECK:    br label %for.body
; CHECK: for.body:
; CHECK:    %convergentD = call i32 @llvm.convergent(i32 %loadD)
; CHECK:    %mulC = mul i32 %convergentD, %loadE
; CHECK: for.end:


; ANALYSIS: for.body.ldist1:
; ANALYSIS-NEXT: Report: unsafe dependent memory operations in loop
; ANALYSIS: for.body:
; ANALYSIS-NEXT: Has convergent operation in loop
; ANALYSIS-NEXT: Report: cannot add control dependency to convergent operation

; convergent instruction happens to block vectorization
; VECTORIZE: call i32 @llvm.convergent
; VECTORIZE: mul i32

for.body:                                         ; preds = %for.body, %entry
  %ind = phi i64 [ 0, %entry ], [ %add, %for.body ]

  %arrayidxA = getelementptr inbounds i32, ptr %a, i64 %ind
  %loadA = load i32, ptr %arrayidxA, align 4

  %arrayidxB = getelementptr inbounds i32, ptr %b, i64 %ind
  %loadB = load i32, ptr %arrayidxB, align 4

  %mulA = mul i32 %loadB, %loadA

  %add = add nuw nsw i64 %ind, 1
  %arrayidxA_plus_4 = getelementptr inbounds i32, ptr %a, i64 %add
  store i32 %mulA, ptr %arrayidxA_plus_4, align 4

  %arrayidxD = getelementptr inbounds i32, ptr %d, i64 %ind
  %loadD = load i32, ptr %arrayidxD, align 4

  %arrayidxE = getelementptr inbounds i32, ptr %e, i64 %ind
  %loadE = load i32, ptr %arrayidxE, align 4

  %convergentD = call i32 @llvm.convergent(i32 %loadD)
  %mulC = mul i32 %convergentD, %loadE

  %arrayidxC = getelementptr inbounds i32, ptr %c, i64 %ind
  store i32 %mulC, ptr %arrayidxC, align 4

  %exitcond = icmp eq i64 %add, 20
  br i1 %exitcond, label %for.end, label %for.body

for.end:                                          ; preds = %for.body
  ret void
}

attributes #0 = { nounwind readnone convergent }
