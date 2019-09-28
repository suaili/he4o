//
//  AIThinkOutPercept.m
//  SMG_NothingIsAll
//
//  Created by jia on 2019/1/24.
//  Copyright © 2019年 XiaoGang. All rights reserved.
//

#import "AIThinkOutPercept.h"
#import "DemandModel.h"
#import "ThinkingUtils.h"
#import "AIPort.h"
#import "TOMvModel.h"
#import "AINet.h"
#import "AIKVPointer.h"
#import "AICMVNode.h"
#import "AIAbsCMVNode.h"
#import "AIFrontOrderNode.h"
#import "AINetAbsFoNode.h"
#import "Output.h"
#import "TOFoModel.h"
#import "AIAbsAlgNode.h"
#import "AIAlgNode.h"
#import "TOAlgScheme.h"

@implementation AIThinkOutPercept

//MARK:===============================================================
//MARK:                     < publicMethod >
//MARK:===============================================================

-(void) dataOut {
    //1. 重排序 & 取当前序列最前的demandModel
    DemandModel *demandModel = nil;
    if (self.delegate && [self.delegate respondsToSelector:@selector(aiThinkOutPercept_GetCurrentDemand)]) {
        demandModel = [self.delegate aiThinkOutPercept_GetCurrentDemand];
    }
    if (!demandModel) return;
    
    //2. energy判断;
    if (![self havEnergy]) {
        return;
    }
    
    //3. 取mvModel_从expCache中,排序并取到首个值得思考的可行outMvModel, 没有则用mvScheme联想一个新的;
    __block TOMvModel *outMvModel = [demandModel getCurSubModel];
    
    //3. 为空,取新的
    if (!outMvModel && demandModel.subModels.count < cTOSubModelLimit) {
        outMvModel = [self dataOut_MvScheme:demandModel];
    }
    
    //TODOTOMORROW:
    //1. 此处,outMvModel取到,解决问题的mvDirection结果,但再往下,仍然是进到反射输出了,,,查为什么行为化失败了,,,
    
    
    //3. 再为空,评价mvModel_无解决经验,则反射输出;
    if (!outMvModel) {
        [self dataOut_ActionScheme:nil];
    }else{
        //4. 有可具象思考的outMvModel则执行;
        [self useEnergy];
        
        //5. 取foModel_联想"解决经验"对应的cmvNode & 联想具象数据,并取到决策关键信息 (foScheme);
        TOModelBase *outFoModel = outMvModel.getCurSubModel;
        
        //5. 为空,取新的
        if (!outFoModel && outMvModel.subModels.count < cTOSubModelLimit) {
            outFoModel = [self dataOut_FoScheme:outMvModel];
        }
        
        //5. 再为空,反馈上一级被不应期;
        if (!outFoModel) {
            [demandModel.except_ps addObject:outMvModel.content_p];//排除无效的outMvModel;
            [self dataOut];
        }else{
            if (ISOK(outFoModel, TOFoModel.class)) {
                TOFoModel *foModel = (TOFoModel*)outFoModel;
                //7. 为空,进行行为化_尝试输出"可行性之首"并找到实际操作 (子可行性判定) (algScheme)
                if (!ARRISOK(foModel.actions)) {
                    [self dataOut_AlgScheme:foModel];
                }
                
                //7. 再为空,反馈上一级被不应期;
                if (!ARRISOK(foModel.actions)) {
                    [outMvModel.except_ps addObject:foModel.content_p];
                    [self dataOut];
                }else{
                    //8. actionScheme (行为方案输出)
                    [self dataOut_ActionScheme:foModel.actions];
                }
            }
        }
    }
}

//MARK:===============================================================
//MARK:                     < privateMethod >
//MARK:===============================================================

/**
 *  MARK:--------------------MvScheme--------------------
 *  功能:
 *      1. 用于找到新的mv经验; (根据index索引找到outMvModel)
 *  注:
 *      1. 目前仅从硬盘找mvNode,因为能解决问题的都几乎被抽象,而太过于具象的又很难行为化;
 */
-(TOMvModel*) dataOut_MvScheme:(DemandModel*)demandModel{
    //1. 判断mv方向
    __block TOMvModel *outMvModel = nil;
    [ThinkingUtils getDemand:demandModel.algsType delta:demandModel.delta complete:^(BOOL upDemand, BOOL downDemand) {
        MVDirection direction = downDemand ? MVDirection_Negative : MVDirection_Positive;
        
        //2. filter筛选器取曾经历的除已有outMvModels之外的最强解决;
        NSArray *mvRefs = [theNet getNetNodePointersFromDirectionReference:demandModel.algsType direction:direction isMem:false filter:^NSArray *(NSArray *protoArr) {
            protoArr = ARRTOOK(protoArr);
            for (NSInteger i = 0; i < protoArr.count; i++) {
                AIPort *port = ARR_INDEX(protoArr, protoArr.count - i - 1);
                BOOL cacheContains = false;
                for (TOMvModel *expCacheItem in demandModel.subModels) {
                    if (port.target_p && [port.target_p isEqual:expCacheItem.content_p]) {
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
            outMvModel = [[TOMvModel alloc] initWithContent_p:referenceMvPort.target_p];
            [demandModel.subModels addObject:outMvModel];
        }
    }];
    [theNV setNodeData:outMvModel.content_p lightStr:@"o0"];
    return outMvModel;
}


/**
 *  MARK:--------------------联想具象foNode--------------------
 *  @param outMvModel : 当前mvModel (具象之旅的出发点);
 *  @result : 返回时序节点地址
 *  1. 从上至下的联想foNode;
 *  注:目前支持每层3个(关联强度前3个),最多3层(具象方向3层);
 *
 *  TODO:加上联想到mv时,传回给demandManager;
 *  注:每一次输出,只是决策与预测上的一环;并不意味着结束;
 *  //1. 记录思考mv结果到叠加demandModel.order;
 *  //3. 如果mindHappy_No,可以再尝试下一个getNetNodePointersFromDirectionReference_Single;找到更好的解决方法;
 *  //4. 最终更好的解决方法被输出,并且解决问题后,被加强;
 *  //5. 是数据决定了下一轮循环思维想什么,但数据仅能通过mv来决定,无论是思考的方向,还是思考的能量,还是思考的目标,都是以mv为准的;而mv的一切关联,又是以数据为规律进行关联的;
 *
 */
-(TOFoModel*) dataOut_FoScheme:(TOMvModel*)outMvModel{
    //1. 数据准备
    if (!ISOK(outMvModel, TOMvModel.class)) {
        return nil;
    }
    AICMVNodeBase *checkMvNode = [SMGUtils searchNode:outMvModel.content_p];
    if (!checkMvNode) {
        return nil;
    }
    
    if (checkMvNode.foNode_p) {
        NSArray *checkFo_ps = @[checkMvNode.foNode_p];
        
        //2. 最多往具象循环三层
        for (NSInteger i = 0; i < cDataOutAssFoDeep; i++) {
            AIFoNodeBase *validFoNode = [ThinkingUtils scheme_GetAValidNode:checkFo_ps except_ps:outMvModel.except_ps checkBlock:nil];
            
            //3. 有效则返回,无效则循环到下一层
            if (ISOK(validFoNode, AIFoNodeBase.class)) {
                TOFoModel *result = [[TOFoModel alloc] initWithContent_p:validFoNode.pointer];
                result.score = [ThinkingUtils dataOut_CheckScore_ExpOut:result.content_p];
                [outMvModel.subModels addObject:result];
                [theNV setNodeData:result.content_p lightStr:@"o1"];
                return result;
            }else{
                checkFo_ps = [ThinkingUtils foScheme_GetNextLayerPs:checkFo_ps];
            }
        }
    }
    
    return nil;
}


/**
 *  MARK:--------------------algScheme--------------------
 *  1. 对条件概念进行判定 (行为化);
 *  2. 理性判定;
 */
-(void) dataOut_AlgScheme:(TOFoModel*)outFoModel{
    //1. 数据准备
    if (!ISOK(outFoModel, TOFoModel.class)) {
        return;
    }
    AIFoNodeBase *foNode = [SMGUtils searchNode:outFoModel.content_p];
    if (!foNode) {
        return;
    }
    
    //2. 进行行为化; (通过有无,变化,等方式,将结构中所有条件概念行为化);
    outFoModel.actions = [TOAlgScheme convert2Out:foNode.content_ps];
}


/**
 *  MARK:--------------------尝试输出信息--------------------
 *  @param outArr : orders里筛选出来的algNode组;
 *
 *  三种输出方式:
 *  1. 反射输出 : reflexOut
 *  2. 激活输出 : absNode信息无conPorts方向的outPointer信息时,将absNode的宏信息尝试输出;
 *  3. 经验输出 : expOut指在absNode或conPort方向有outPointer信息;
 *
 *  功能: 将行为概念组成的长时序,转化为真实输出;
 *  1. 找到行为的具象;
 *  2. 正式执行行为 (小脑);
 */
-(void) dataOut_ActionScheme:(NSArray*)outArr{
    //1. 尝试输出找到解决问题的实际操作 (取到当前cacheModel中的最佳决策,并进行输出;)
    BOOL tryOutSuccess = false;
    if (ARRISOK(outArr)) {
        for (AIKVPointer *algNode_p in outArr) {
            //>1 检查micro_p是否是"输出";
            //>2 假如order_p足够确切,尝试检查并输出;
            BOOL invoked = [Output output_TC:algNode_p];
            [theNV setNodeData:algNode_p lightStr:@"o3"];
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
        
        //1. 心急情绪释放,平复思维;
        [self useEnergy];
        
        //2. 反射输出
        [Output output_Mood:AIMoodType_Anxious];
    }
}

//MARK:===============================================================
//MARK:                     < private_Method >
//MARK:===============================================================
//使用能量
-(void) useEnergy{
    if (self.delegate && [self.delegate respondsToSelector:@selector(aiThinkOutPercept_UpdateEnergy:)]) {
        [self.delegate aiThinkOutPercept_UpdateEnergy:-1];//思考与决策消耗能量;
    }
}

//拥有能量
-(BOOL) havEnergy{
    if (self.delegate && [self.delegate respondsToSelector:@selector(aiThinkOutPercept_EnergyValid)]) {
        return [self.delegate aiThinkOutPercept_EnergyValid];
    }
    return false;
}

@end


/**
 *  MARK:--------------------algScheme--------------------
 *  1. 将fo.orders转换为memOrder;
 *  2. 对条件概念取最具象 (目前仅支持1层);
 *
 *  注: 最具象不表示真实,所以此方法可考虑去掉;
 *  注: 190425,废弃"memOrder"和"最具象概念"后备份于此;
 */
//-(void) dataOut_AlgScheme_Front:(TOFoModel*)outFoModel{
//    //1. 数据准备
//    if (!ISOK(outFoModel, TOFoModel.class)) {
//        return;
//    }
//    AIFoNodeBase *foNode = [SMGUtils searchObjectForPointer:outFoModel.content_p fileName:kFNNode time:cRTNode];
//    if (!foNode) {
//        return;
//    }
//
//    //废弃"memOrder"和"最具象概念"
//    [outFoModel.memOrder removeAllObjects];
//
//    2. 取条件概念的最具象,得出memOrder;
//    //NSLog(@" >> 所需条件: (%@)",[NVUtils convertOrderPs2Str:notOutAlg_ps]);
//    for (AIKVPointer *pointer in foNode.content_ps) {
//        ///1. 本身为输出节点的话,直接收集到memOrder
//        if (pointer.isOut) {
//            AIAlgNodeBase *outAlgNode = [SMGUtils searchObjectForPointer:pointer fileName:kFNNode time:cRTNode];
//            if (outAlgNode) {
//                [outFoModel.memOrder addObject:outAlgNode];
//            }
//        }else{
//            ///2. 非输出时,找出条件概念,并收集到memOrder (最多往具象循环2层) (最具象不表示真实,所以此处可以考虑去掉)
//            NSArray *check_ps = @[pointer];
//            for (NSInteger i = 0; i < cDataOutAssAlgDeep; i++) {
//                AIAlgNode *validAlgNode = [ThinkingUtils scheme_GetAValidNode:check_ps except_ps:outFoModel.except_ps checkBlock:^BOOL(id checkNode) {
//                    return ISOK(checkNode, AIAlgNode.class);
//                }];
//
//                //3. 有效则返回,无效则循环到下一层
//                if (ISOK(validAlgNode, AIAlgNode.class)) {
//                    [outFoModel.memOrder addObject:validAlgNode];
//                }else{
//                    check_ps = [ThinkingUtils algScheme_GetNextLayerPs:check_ps];
//                }
//            }
//        }
//    }
//
//    //3. 对memOrder有效性初步检查 (memOrder和fo.orders长度要一致)
//    if (outFoModel.memOrder.count == foNode.content_ps.count) {
//        [self dataOut_AlgScheme:outFoModel];
//    }else{
//        [self dataOut];
//    }
//}