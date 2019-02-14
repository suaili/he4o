//
//  AIThinkOut.m
//  SMG_NothingIsAll
//
//  Created by jia on 2019/1/24.
//  Copyright © 2019年 XiaoGang. All rights reserved.
//

#import "AIThinkOut.h"
#import "DemandModel.h"
#import "ThinkingUtils.h"
#import "AIPort.h"
#import "AIThinkOutMvModel.h"
#import "AINet.h"
#import "AIKVPointer.h"
#import "AICMVNode.h"
#import "AIAbsCMVNode.h"
#import "AIFrontOrderNode.h"
#import "AINetAbsFoNode.h"
#import "Output.h"

@implementation AIThinkOut

//MARK:===============================================================
//MARK:                     < publicMethod >
//MARK:===============================================================

-(void) dataOut {
    //1. 重排序 & 取当前序列最前;
    if (self.delegate && [self.delegate respondsToSelector:@selector(aiThinkOut_GetCurrentDemand)] && [self.delegate respondsToSelector:@selector(aiThinkOut_EnergyValid)]) {
        DemandModel *demandModel = [self.delegate aiThinkOut_GetCurrentDemand];
        if (demandModel != nil) {
            
            //2. energy判断;
            if ([self.delegate aiThinkOut_EnergyValid]) {
                //3. 从expCache中,排序并取到首个值得思考的outMvModel;
                __block AIThinkOutMvModel *outMvModel = [demandModel getCurrentAIThinkOutMvModel];
                
                //4. mvScheme (如果,没有一个想可行的,则再联想一个新的相关"解决经验";并重新循环下去;)
                if (!outMvModel) {
                    outMvModel = [self dataOut_IndexScheme:demandModel];
                }
                
                //5. 有可具象思考的outMvModel则执行;
                if (outMvModel) {
                    if (self.delegate && [self.delegate respondsToSelector:@selector(aiThinkOut_UpdateEnergy:)]) {
                        [self.delegate aiThinkOut_UpdateEnergy:-1];//思考与决策消耗能量;
                    }
                    
                    //6. foScheme (联想"解决经验"对应的cmvNode & 联想具象数据,并取到决策关键信息;(可行性判定))
                    [self dataOut_MvFoScheme:outMvModel complete:^(BOOL canOut, NSArray *out_ps,BOOL outMvModelInvalid) {
                        if (canOut) {
                            
                            //7. actionScheme (行为方案输出)
                            [self dataOut_ActionScheme:out_ps];
                        }else{
                            if (outMvModelInvalid) {
                                [demandModel.exceptOutMvModels addObject:outMvModel];  //排除无效的outMvModel;(一次无效,不表示永远无效,所以彻底无效时,再排除)
                            }
                            [self dataOut];               //并递归到最初;
                        }
                    }];
                }else{
                    //8. 无解决经验,反射输出;//V2TODO:此处不应放弃联想,应该先看下当前有哪些信息,是可以联想分析出解决方案的; (跳出递归)
                    [self dataOut_ActionScheme:nil];
                }
            }else{
                //9. 如果energy<=0,(未找到可行性,直接反射输出 || 尝试输出"可行性之首"并找到实际操作)
                [self dataOut_ActionScheme:nil];
            }
        }
    }
}

//MARK:===============================================================
//MARK:                     < privateMethod >
//MARK:===============================================================

/**
 *  MARK:--------------------indexScheme--------------------
 *  用于找到新的mv经验; (根据index索引找到outMvModel)
 */
-(AIThinkOutMvModel*) dataOut_IndexScheme:(DemandModel*)demandModel{
    //1. 判断mv方向
    __block AIThinkOutMvModel *outMvModel = nil;
    [ThinkingUtils getDemand:demandModel.algsType delta:demandModel.delta complete:^(BOOL upDemand, BOOL downDemand) {
        MVDirection direction = downDemand ? MVDirection_Negative : MVDirection_Positive;
        
        //2. filter筛选器取曾经历的除已有outMvModels之外的最强解决;
        NSArray *mvRefs = [theNet getNetNodePointersFromDirectionReference:demandModel.algsType direction:direction filter:^NSArray *(NSArray *protoArr) {
            protoArr = ARRTOOK(protoArr);
            for (NSInteger i = 0; i < protoArr.count; i++) {
                AIPort *port = ARR_INDEX(protoArr, protoArr.count - i - 1);
                BOOL cacheContains = false;
                for (AIThinkOutMvModel *expCacheItem in demandModel.outMvModels) {
                    if (port.target_p && [port.target_p isEqual:expCacheItem.mvNode_p]) {
                        cacheContains = true;
                        break;
                    }
                }
                if (!cacheContains) {
                    return @[port];
                }
            }
            return nil;
        }];
        
        //3. 加入待判断区;
        AIPort *referenceMvPort = ARR_INDEX(mvRefs, 0);
        if (referenceMvPort) {
            outMvModel = [AIThinkOutMvModel newWithExp_p:referenceMvPort.target_p];
            [demandModel addToExpCache:outMvModel];
        }
    }];
    return outMvModel;
}


/**
 *  MARK:--------------------MvFoScheme--------------------
 *  @param outMvModel : 从outMvModel下查找具象可输出;
 *  联想具象 (从上往下找foNode)
 */
-(void) dataOut_MvFoScheme:(AIThinkOutMvModel*)outMvModel complete:(void(^)(BOOL canOut,NSArray *out_ps,BOOL outMvModelInvalid))complete{
    
    //1. 从抽象方向找到fo节点;
    //2. 评价fo节点;
    //3. 筛选出out_ps和 "条件"
    //4. 注: 目前条件为"视觉看到的坚果" (已抽象的,如无距离)
    //5. 难点: 在于如何去满足这个条件;
    //6. 在外界去找到"条件";
    
    
    
    __block BOOL invokedComplete = false;
    __block BOOL outMvModelInvalid = false;
    if (outMvModel) {
        //1. 联想"解决经验"对应的cmvNode & 联想具象数据,并取到决策关键信息;(可行性判定)
        AICMVNodeBase *expMvNode = [SMGUtils searchObjectForPointer:outMvModel.mvNode_p fileName:FILENAME_Node time:cRedisNodeTime];
        
        
        
        //明日计划;
        //1. 从抽象方向开始找foNode (而不是当前的具象方向);
        //2. 对找到的absFoNode装成outFoModel & 对条件进行判定;
        
        
        
        //明日计划;
        //1. 找到抽象foNode;
        //2. 把absFoNode中isOut部分跳过,其他为所需条件部分;
        //3. 到祖母中,对所需条件和已有条件进行类比,并分析出不同 (如距离)
        //4. 回归到fo找出能够让 "距离变化" 的时序,并找到行为方式 (如飞行)
        //5. 执行输出;
        //6. 视觉输入,(对outModel中的数据进行判定效果,继续执行决策)
        //先写一些伪代码;把以上步骤定义好结构架子;
        
        
        
        //TODONextYear: 从抽象往具象,往alg两个方向找实现方式与条件;
        AIFrontOrderNode *expOutFoNode = nil;
        
        //2. 有执行方案,则对执行方案进行反思检查;
        if (expOutFoNode != nil) {
            [ThinkingUtils dataOut_CheckScore_ExpOut:expOutFoNode complete:^(CGFloat score, NSArray *out_ps) {
                outMvModel.order += score;//联想对当前outMvModel的order影响;
                NSLog(@" >> 执行经验输出: (%@) (%f) (%@)",score >= 3 ? @"成功" : @"失败",score,[NVUtils convertOrderPs2Str:out_ps]);
                if (score >= 3) {
                    complete(true,out_ps,outMvModelInvalid);
                    invokedComplete = true;
                }
            }];
        }else{
            //4. 没有执行方案,转向对抽象宏节点进行尝试输出;
            AINetAbsFoNode *tryOutAbsNode = [self dataOut_FoScheme:expMvNode exceptFo_ps:outMvModel.exceptTryOut_ps];
            if (tryOutAbsNode != nil) {
                [ThinkingUtils dataOut_CheckScore_TryOut:tryOutAbsNode complete:^(CGFloat score, NSArray *out_ps) {
                    outMvModel.order += score;//联想对当前outMvModel的order影响;
                    NSLog(@" >> 执行尝试输出: (%@) (%f) (%@)",score > 10 ? @"成功" : @"失败",score,[NVUtils convertOrderPs2Str:out_ps]);
                    if (score > 10) {
                        complete(true,out_ps,outMvModelInvalid);
                        invokedComplete = true;
                    }
                }];
            }else{
                //5. 本outMvModel彻底无效,
                outMvModelInvalid = true;
            }
        }
    }
    
    if (!invokedComplete) {
        NSLog(@" >> 本次输出不过关,toLoop...");
        complete(false,nil,outMvModelInvalid);
    }
}


/**
 *  MARK:--------------------联想具象 (从上往下找foNode)--------------------
 *  TODO:加上联想到mv时,传回给demandManager;
 *  注:每一次输出,只是决策与预测上的一环;并不意味着结束;
 *  //1. 记录思考mv结果到叠加demandModel.order;
 *  //3. 如果mindHappy_No,可以再尝试下一个getNetNodePointersFromDirectionReference_Single;找到更好的解决方法;
 *  //4. 最终更好的解决方法被输出,并且解决问题后,被加强;
 *  //5. 是数据决定了下一轮循环思维想什么,但数据仅能通过mv来决定,无论是思考的方向,还是思考的能量,还是思考的目标,都是以mv为准的;而mv的一切关联,又是以数据为规律进行关联的;
 *  注: 先从最强关联的最底层foNode开始,逐个取用;直到energy<=0,或其它原因中止;
 *
 */



/**
 *  MARK:--------------------联想具象 (从下往上找absNode)--------------------
 *  @param expMvNode :  当前在判断的mv节点经验(有可能是AICMVNode也有可能是AIAbsCMVNode)
 *  @result : 返回前因节点地址(仅absNode_p,不要foNode_p)
 *  功能 : 找可尝试输出 (激活输出);
 *  1. 从上至下的联想absNode;
 *  注:目前仅支持每层1个,与最分支向下联想,即abs的最强关联的下层前1;
 */
-(AINetAbsFoNode*) dataOut_FoScheme:(AICMVNodeBase*)checkMvNode exceptFo_ps:(nonnull NSMutableArray*)exceptTryOut_ps{
    
    
    //1. 从checkMvNodes获取有效一条并返回;
    //    AINetAbsFoNode*(^ getFoNode)(NSArray* checkMvNodes,NSArray *exceptMv_ps) = ^(NSArray* checkMvNodes,NSArray *exceptMv_ps){
    //        ///1. 数据检查
    //        if (!ARRISOK(checkMvNodes)) {
    //            return nil;
    //        }
    //
    //        ///2. 判断是否已排除
    //        for (AIAbsCMVNode *checkMvNode in checkMvNodes) {
    //            if(ISOK(checkMvNode, AIAbsCMVNode.class)){
    //                //2. 未排除,返回;
    //                if ([SMGUtils containsSub_p:checkMvNode.pointer parent_ps:exceptTryOut_ps]) {
    //                    [exceptTryOut_ps addObject:checkMvNode.foNode_p];
    //                    AINetAbsFoNode *result = [SMGUtils searchObjectForPointer:checkMvNode.foNode_p fileName:FILENAME_Node time:cRedisNodeTime];
    //                    return result;
    //                }
    //            }
    //        }
    //        return nil;
    //    };
    
    //1. 数据准备
    if (!ISOK(checkMvNode, AICMVNodeBase.class)) {
        return nil;
    }
    if (checkMvNode.foNode_p) {
        AINetAbsFoNode *result = [ThinkingUtils foScheme_GetFoNode:@[checkMvNode.foNode_p] exceptMv_ps:exceptTryOut_ps];
        
        if (result) {
            return result;
        }else{
            NSArray *nextFo_ps = [ThinkingUtils foScheme_GetNextLayerPs:@[checkMvNode.foNode_p]];
            
            
            //TODOTOMORROW:改成3层for循环;
            
            
            
            
            
            
            
            
        }
        
    }
    
    return nil;
}



    


/**
 *  MARK:--------------------algScheme--------------------
 *  1. 对祖母条件进行判定;
 */
-(void) dataOut_AlgScheme{
    
}


/**
 *  MARK:--------------------尝试输出信息--------------------
 *  @param outArr : orders里筛选出来的algNode组;
 *
 *  三种输出方式:
 *  1. 反射输出 : reflexOut
 *  2. 激活输出 : absNode信息无conPorts方向的outPointer信息时,将absNode的宏信息尝试输出;
 *  3. 经验输出 : expOut指在absNode或conPort方向有outPointer信息;
 */
-(void) dataOut_ActionScheme:(NSArray*)outArr{
    //1. 尝试输出找到解决问题的实际操作 (取到当前cacheModel中的最佳决策,并进行输出;)
    BOOL tryOutSuccess = false;
    if (ARRISOK(outArr)) {
        for (AIKVPointer *algNode_p in outArr) {
            //>1 检查micro_p是否是"输出";
            //>2 假如order_p足够确切,尝试检查并输出;
            BOOL invoked = [Output output_TC:algNode_p];
            if (invoked) {
                tryOutSuccess = true;
            }
        }
    }
    
    //2. 无法解决时,反射一些情绪变化,并增加额外输出;
    if (!tryOutSuccess) {
        //>1 产生"心急mv";(心急产生只是"urgent.energy x 2")
        //>2 输出反射表情;
        //>3 记录log到foOrders;(记录log应该到output中执行)
        
        //1. 如果未找到复现方式,或解决方式,则产生情绪:急
        //2. 通过急,输出output表情哭
        NSLog(@"反射输出 >>");
        [Output output_Mood:AIMoodType_Anxious];
    }
}

@end
